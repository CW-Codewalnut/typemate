import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/core/audio/record_package_audio.dart';
import 'src/core/diagnostics/diagnostic_log.dart';
import 'src/core/diagnostics/diagnostic_reporter.dart';
import 'src/core/dictation_history_controller.dart';
import 'src/core/platform/android/native_dictation_channel.dart';
import 'src/core/stt/android_speech_runtime.dart';
import 'src/core/diagnostics/sentry_telemetry.dart';
import 'src/core/diagnostics/telemetry_controller.dart';
import 'src/models/app_identity.dart';

/// Anonymous error reporting backend. Injected at build time
/// (`--dart-define=TYPEMATE_SENTRY_DSN=...`); when absent — every local
/// dev build — telemetry is entirely off and the Settings toggle hides.
const _sentryDsn = String.fromEnvironment('TYPEMATE_SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android has no window manager, tray, single-instance concern, or
  // desktop notifier; it bootstraps on its own leaner path.
  if (Platform.isAndroid) {
    await _runAndroidApp();
    return;
  }
  // One TypeMate only: a second launch would fight over the global
  // shortcut and the resident speech servers. Hand focus to the running
  // instance and bow out.
  if (!await FlutterSingleInstance().isFirstInstance()) {
    await FlutterSingleInstance().focus();
    exit(0);
  }
  // When a second launch pings us, surface the existing window — including
  // un-hiding it from the tray, which a bare focus() cannot do.
  FlutterSingleInstance.onFocus = (_) async {
    await windowManager.show();
    await windowManager.focus();
  };

  // Desktop speech models download on demand (slim installs). Persist
  // task records so a relaunch can tell a COMPLETE download (killed
  // between finish and rename) from a stale one: desktop downloads die
  // with the app, so anything still marked running is cleared and
  // restarted, never adopted (that wedged the progress bar before).
  await FileDownloader().trackTasks();

  final diagnosticLog = createDefaultDiagnosticLog();
  final telemetryController = TelemetryController(
    store: createDefaultTelemetrySettingsStore(),
    dsn: _sentryDsn,
    telemetrySink: const SentryTelemetrySink(),
    startTelemetry: () => startSentryTelemetry(_sentryDsn),
    stopTelemetry: stopSentryTelemetry,
  );
  final diagnosticReporter = DiagnosticReporter(
    log: diagnosticLog,
    telemetrySink: telemetryController,
  );
  diagnosticReporter.info(
    'app',
    'TypeMate starting: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}, '
        '${Platform.numberOfProcessors} CPU cores, '
        'locale ${Platform.localeName}',
  );
  // Framework errors go to the local log; Sentry's own integration (when
  // telemetry is on) captures them remotely, so no failure() here — that
  // would double-report.
  final defaultFlutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnosticLog.log('app', 'flutter-error: ${details.exceptionAsString()}');
    defaultFlutterOnError?.call(details);
  };
  // Reads the persisted consent and starts Sentry when enabled + DSN set.
  await telemetryController.load();

  // Hide the native title bar on every desktop: WindowTitleBar draws one
  // Flutter bar (white, Windows-style) so the chrome is identical on all
  // OSes instead of following each window manager's theme.
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  // Below this the layout genuinely breaks (the nav rail, download card,
  // and mic FAB start colliding); the layout is responsive down to here.
  await windowManager.setMinimumSize(const Size(480, 520));
  // The OS-visible window title (taskbar, alt-tab) derives from the same
  // constant as every in-app surface.
  await windowManager.setTitle(appDisplayName);
  runApp(
    TypeMateApp(
      diagnosticReporter: diagnosticReporter,
      telemetryController: telemetryController,
    ),
  );
}

/// Android bootstrap. Dictation runs inside the app (no global shortcut or
/// tray), so none of the desktop window plumbing applies. Per-user data
/// lives in the app's private support directory — Android has no
/// APPDATA/XDG environment to derive it from.
Future<void> _runAndroidApp() async {
  final dataDirectory = await getApplicationSupportDirectory();
  // The one-time model download keeps going while the app is in the
  // background; the notification is how the user sees that. The task
  // must run as a FOREGROUND service: a plain background job gets
  // stopped by the OS seconds after the app leaves the foreground
  // (JobScheduler onStopJob, observed on Android 16).
  await FileDownloader().configure(
    androidConfig: [(Config.runInForegroundIfFileLargerThan, 0)],
  );
  // Persist task records: if the process dies mid-download (swiped from
  // recents), WorkManager finishes the file anyway and the next attempt
  // finds and reuses it instead of starting over.
  await FileDownloader().trackTasks();
  FileDownloader().configureNotification(
    running: speechModelDownloadNotification,
    progressBar: true,
  );
  // Same local error log as desktop, in the app's private files; Settings
  // offers it through the system share sheet (no browsable folder on
  // Android).
  final diagnosticLog = DiagnosticLog(
    file: File('${dataDirectory.path}/logs/typemate.log'),
  );
  final telemetryController = TelemetryController(
    store: createDefaultTelemetrySettingsStore(directory: dataDirectory),
    dsn: _sentryDsn,
    telemetrySink: const SentryTelemetrySink(),
    startTelemetry: () => startSentryTelemetry(_sentryDsn),
    stopTelemetry: stopSentryTelemetry,
  );
  final diagnosticReporter = DiagnosticReporter(
    log: diagnosticLog,
    telemetrySink: telemetryController,
  );
  diagnosticReporter.info(
    'app',
    'TypeMate starting: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}, '
        '${Platform.numberOfProcessors} CPU cores, '
        'locale ${Platform.localeName}',
  );
  final defaultFlutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnosticLog.log('app', 'flutter-error: ${details.exceptionAsString()}');
    defaultFlutterOnError?.call(details);
  };
  await telemetryController.load();
  runApp(
    TypeMateApp(
      diagnosticReporter: diagnosticReporter,
      telemetryController: telemetryController,
      dataDirectory: dataDirectory,
    ),
  );
}

/// Entry point for the native Android dictation surfaces (the floating
/// mic overlay and the physical-keyboard shortcut). The accessibility
/// service hosts a headless Flutter engine running this instead of the
/// app UI: no widgets, just the dictation channel wired to the same
/// on-device speech stack the app uses. The model must already be
/// provisioned by the app; the overlay only reports that, it never
/// downloads.
@pragma('vm:entry-point')
Future<void> dictationServiceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDirectory = await getApplicationSupportDirectory();
  // The floating mic follows the language selected in the app. The
  // headless engine has no settings controller, so the persisted setting
  // is re-read before every dictation (beforeDictation below).
  final speechSettingsStore = createDefaultSpeechSettingsStore(
    directory: dataDirectory,
  );
  var languageCode = 'en';
  Future<void> refreshLanguage() async {
    languageCode = (await speechSettingsStore.load()).languageCode;
  }

  await refreshLanguage();
  final speechRuntime = createSpeechRuntime(
    dataDirectoryPath: dataDirectory.path,
    languageCodeProvider: () => languageCode,
  );
  // Unlike the app path, this must NOT route through the record plugin's
  // permission request: that needs a foreground Activity, and a headless
  // engine has none. The Kotlin service preflights the permission before
  // every dictation instead.
  final recorderFactory = RecordPackageAudioRecorderFactory(
    outputDirectory: createDefaultRecordingsDirectory(directory: dataDirectory),
    useSystemDefaultDevice: true,
  );
  // Floating-mic dictations land in the same history file the app reads
  // (reloaded there on resume). Reload before each write: the app engine
  // writes the same file (retry, clear), and appending onto a stale copy
  // would resurrect deleted entries.
  final historyController = DictationHistoryController(
    store: createDefaultDictationHistoryStore(directory: dataDirectory),
  );
  registerNativeDictationChannel(
    NativeDictationHandler(
      engine: speechRuntime.engine,
      recorderFactory: recorderFactory,
      provisioner: speechRuntime.provisioner,
      beforeDictation: refreshLanguage,
      onTranscriptGenerated: (transcript, {required duration}) async {
        await historyController.load();
        await historyController.addTranscript(transcript, duration: duration);
      },
    ),
  );
}
