import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/core/diagnostics/diagnostic_log.dart';
import 'src/core/diagnostics/diagnostic_reporter.dart';
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
  // OS notifications for dictation failures: they must reach the user even
  // while the app sits in the tray. Windows toasts require a Start Menu
  // shortcut with the app's identity, which setup ensures.
  await localNotifier.setup(
    appName: appDisplayName,
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
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
  // No local log file on Android: the Settings surface that lets a user
  // find and share it is desktop-only, and a log nobody can see should
  // not be written. Opt-in Sentry telemetry remains the diagnostics path.
  const diagnosticLog = DiagnosticLog.disabled();
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
