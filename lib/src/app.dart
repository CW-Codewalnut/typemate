import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'components/app_scroll_behavior.dart';
import 'components/window_title_bar.dart';
import 'core/audio/audio_denoiser.dart';
import 'core/audio/microphone_discovery.dart';
import 'core/audio/microphone_audio_recorder_factory.dart';
import 'core/audio/system_default_microphone_discovery.dart';
import 'core/audio/record_package_audio.dart';
import 'core/diagnostics/diagnostic_log.dart';
import 'core/diagnostics/diagnostic_reporter.dart';
import 'core/diagnostics/telemetry_controller.dart';
import 'core/dictation_controller.dart';
import 'core/dictation_history_controller.dart';
import 'core/hold_shortcut_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'core/microphone_settings_store.dart';
import 'core/speech_settings_controller.dart';
import 'core/platform/android/android_platform_bridge.dart';
import 'core/platform/android/floating_mic_controller.dart';
import 'core/platform/linux/linux_platform_bridge.dart';
import 'core/platform/linux/linux_x11_hold_shortcut_registrar.dart';
import 'core/platform/macos/macos_platform_bridge.dart';
import 'core/platform/macos/macos_polling_hold_shortcut_registrar.dart';
import 'core/platform/mock_platform_bridge.dart';
import 'core/platform/platform_bridge.dart';
import 'core/platform/windows/windows_platform_bridge.dart';
import 'core/platform/windows/windows_polling_hold_shortcut_registrar.dart';
import 'core/stt/android_speech_runtime.dart';
import 'core/stt/desktop_speech_runtime.dart';
import 'core/stt/stt_engine.dart';
import 'core/stt/stt_model_provisioner.dart';
import 'features/home/home_screen.dart';
import 'models/app_identity.dart';
import 'theme/app_theme.dart';

export 'core/stt/desktop_speech_runtime.dart';

class TypeMateApp extends StatefulWidget {
  const TypeMateApp({
    super.key,
    this.microphoneDiscovery,
    this.holdShortcutRegistrar,
    this.sttEngine,
    this.platformBridge,
    this.audioRecorderFactory,
    this.audioDenoiser,
    this.diagnosticReporter,
    this.telemetryController,
    this.dataDirectory,
    this.useMobileShell,
    this.modelProvisioner,
  });

  final MicrophoneDiscovery? microphoneDiscovery;
  final HoldShortcutRegistrar? holdShortcutRegistrar;
  final SttEngine? sttEngine;
  final PlatformBridge? platformBridge;
  final AudioRecorderFactory? audioRecorderFactory;
  final AudioDenoiser? audioDenoiser;

  /// Diagnostics funnel created in main(); tests that omit it run with a
  /// disabled local log and no telemetry.
  final DiagnosticReporter? diagnosticReporter;

  /// Error-reporting consent state, surfaced as the Settings toggle.
  final TelemetryController? telemetryController;

  /// Overrides where settings and history files live. Tests point this at a
  /// temp directory so end-to-end runs never touch real user data.
  final Directory? dataDirectory;

  /// Mobile experience: in-app dictation tab, no window title bar, no
  /// shortcut/quit/noise-suppression settings, Parakeet-only languages.
  /// Defaults to the platform (Android); tests can force it on desktop.
  final bool? useMobileShell;

  /// Overrides the speech model download state; tests pair it with a mock
  /// [sttEngine].
  final SpeechModelProvisioner? modelProvisioner;

  @override
  State<TypeMateApp> createState() => _TypeMateAppState();
}

class _TypeMateAppState extends State<TypeMateApp> {
  late final DictationController controller;
  late final DictationHistoryController historyController;
  late final MicrophoneSettingsController microphoneController;
  late final SpeechSettingsController speechSettingsController;
  late final HoldShortcutController shortcutController;
  late final PlatformBridge platformBridge;
  late final SttEngine _sttEngine;
  late final DiagnosticReporter _diagnostics;
  late final bool _useMobileShell;
  SpeechModelProvisioner? _modelProvisioner;
  FloatingMicController? _floatingMicController;
  late String _lastPreparedLanguageCode;
  AudioDenoiser? _audioDenoiser;

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.diagnosticReporter ?? DiagnosticReporter();
    _useMobileShell = widget.useMobileShell ?? Platform.isAndroid;
    if (_useMobileShell) {
      _floatingMicController = FloatingMicController();
    }
    final recordingsDirectory = createDefaultRecordingsDirectory(
      directory: widget.dataDirectory,
    );
    // Dictation audio is transcribe-and-delete; sweep anything a crash or
    // an older build left behind so no speech sits on disk. Older builds
    // recorded into a CWD-relative build/recordings, so sweep the copy
    // next to the executable too.
    unawaited(purgeStaleRecordings(recordingsDirectory));
    unawaited(
      purgeStaleRecordings(
        Directory(
          '${File(Platform.resolvedExecutable).parent.path}/build/recordings',
        ),
      ),
    );
    final recorderFactory =
        widget.audioRecorderFactory ??
        createDefaultAudioRecorderFactory(outputDirectory: recordingsDirectory);
    microphoneController = MicrophoneSettingsController(
      discovery:
          widget.microphoneDiscovery ?? createDefaultMicrophoneDiscovery(),
      store: createDefaultMicrophoneSettingsStore(
        directory: widget.dataDirectory,
      ),
    );
    historyController = DictationHistoryController(
      store: createDefaultDictationHistoryStore(
        directory: widget.dataDirectory,
      ),
    );
    speechSettingsController = SpeechSettingsController(
      store: createDefaultSpeechSettingsStore(directory: widget.dataDirectory),
    );
    platformBridge = widget.platformBridge ?? createDefaultPlatformBridge();
    final injectedEngine = widget.sttEngine;
    if (injectedEngine != null) {
      _sttEngine = injectedEngine;
      _modelProvisioner = widget.modelProvisioner;
    } else if (Platform.isAndroid) {
      // Android cannot spawn the bundled desktop servers; it runs the same
      // Parakeet model in-process, downloaded on first run.
      final dataDirectory = widget.dataDirectory;
      if (dataDirectory == null) {
        throw StateError(
          'Android bootstrap must provide dataDirectory (see main.dart).',
        );
      }
      final speechRuntime = createAndroidSpeechRuntime(
        dataDirectory: dataDirectory,
        diagnostics: _diagnostics,
      );
      _sttEngine = speechRuntime.engine;
      _modelProvisioner = speechRuntime.provisioner;
      // In-process GTCRN denoiser, same as desktop; its tiny model rides
      // the first-run download.
      _audioDenoiser = speechRuntime.denoiser;
    } else {
      // Desktop: in-process Parakeet plus per-language whisper servers.
      // Models the install did not bundle download on demand into the
      // per-user data directory.
      final runtime = createDesktopSpeechRuntime(
        dataDirectoryPath:
            (widget.dataDirectory ?? _typeMateDataDirectory()).path,
        languageCodeProvider: () => speechSettingsController.languageCode,
        diagnostics: _diagnostics,
      );
      _sttEngine = runtime.engine;
      _modelProvisioner = runtime.provisioner;
    }
    if (platformBridge case final QuitRequestSource quitSource) {
      quitSource.onQuitRequested = _shutDownAndExit;
    }
    controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: _sttEngine,
      diagnostics: _diagnostics,
      readyStatusMessage: _useMobileShell
          ? 'Ready. Hold the mic button and speak.'
          : DictationController.defaultReadyStatusMessage,
      // A dictation cannot succeed before the selected language's model is
      // downloaded; refuse the attempt (hotkey or mic tile) with the
      // reason instead of recording into a guaranteed failure.
      dictationBlocker: () {
        final provisioner = _modelProvisioner;
        if (provisioner != null && !provisioner.isReady) {
          return 'Download the speech model in the TypeMate window first.';
        }
        return null;
      },
      onTranscriptGenerated: historyController.addTranscript,
      onTranscriptionFailed: historyController.addFailure,
      audioRecorderProvider: () {
        final selectedMicrophone = microphoneController.selectedMicrophone;
        if (selectedMicrophone == null) {
          return null;
        }

        return recorderFactory.create(selectedMicrophone);
      },
      // Resolved lazily on the first noise-suppressed dictation so an
      // install without the optional denoiser runtime still boots and
      // dictates; the toggle then simply has nothing to run.
      audioDenoiserProvider: () {
        if (!speechSettingsController.noiseSuppressionEnabled) {
          return null;
        }
        return _audioDenoiser ??=
            widget.audioDenoiser ?? createDefaultAudioDenoiser();
      },
    );
    shortcutController = HoldShortcutController(
      dictationController: controller,
      registrar:
          widget.holdShortcutRegistrar ?? createDefaultHoldShortcutRegistrar(),
      store: createDefaultHoldShortcutSettingsStore(
        directory: widget.dataDirectory,
      ),
    );
    shortcutController.register();
    unawaited(platformBridge.ensureLaunchAtStartup());
    historyController.load();
    speechSettingsController.load();
    // Swap resident speech servers as soon as the language changes so the
    // newly selected model is warm before the next dictation, and the old
    // one's RAM is released.
    _lastPreparedLanguageCode = speechSettingsController.languageCode;
    speechSettingsController.addListener(_onLanguageChanged);
    // Linux: closing the window hides it instead of quitting (the runner's
    // delete-event handler owns this), so dictation keeps running in the
    // background like the Windows tray build. Quit lives in Settings.
  }

  void _onLanguageChanged() {
    // The controller also notifies for non-language settings (the noise
    // suppression toggle); only an actual language change swaps servers.
    if (speechSettingsController.languageCode == _lastPreparedLanguageCode) {
      return;
    }
    _lastPreparedLanguageCode = speechSettingsController.languageCode;
    unawaited(_prepareForSelectedLanguage());
  }

  /// Warms the newly selected language's engine — unless its model is not
  /// downloaded yet, in which case the dictation surface offers the
  /// download and preparation happens once it completes.
  Future<void> _prepareForSelectedLanguage() async {
    final provisioner = _modelProvisioner;
    if (provisioner != null) {
      await provisioner.refresh();
      if (!provisioner.isReady) {
        return;
      }
    }
    try {
      await _sttEngine.prepare();
    } catch (_) {
      // Preloading is best-effort; a failure surfaces on the next
      // dictation with a proper error state.
    }
  }

  /// Answers the tray's Quit request: stop the resident speech server, then
  /// end the process (the native side force-quits if this never returns).
  Future<void> _shutDownAndExit() async {
    final engine = _sttEngine;
    if (engine is DisposableSttEngine) {
      await engine.shutdown();
    }
    exit(0);
  }

  @override
  void dispose() {
    speechSettingsController.removeListener(_onLanguageChanged);
    final engine = _sttEngine;
    if (engine is DisposableSttEngine) {
      unawaited(engine.shutdown());
    }
    shortcutController.dispose();
    speechSettingsController.dispose();
    historyController.dispose();
    microphoneController.dispose();
    _modelProvisioner?.dispose();
    _floatingMicController?.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: buildAppTheme(),
      // On Linux the native frame is hidden (undecorated), so the frame
      // widget restores edge resizing; Windows keeps its native edges.
      builder: (context, child) =>
          Platform.isLinux ? VirtualWindowFrame(child: child!) : child!,
      home: Column(
        children: [
          if (!_useMobileShell) const WindowTitleBar(),
          Expanded(
            child: HomeScreen(
              controller: controller,
              historyController: historyController,
              microphoneController: microphoneController,
              speechSettingsController: speechSettingsController,
              // Mobile hides every desktop-only Settings surface: no global
              // shortcut, no file-manager log folder, no Quit (Android
              // lifecycles apps itself).
              shortcutController: _useMobileShell ? null : shortcutController,
              telemetryController: widget.telemetryController,
              logsDirectoryPath: _useMobileShell
                  ? null
                  : _diagnostics.log.directoryPath,
              // Mobile has no user-browsable folder; the log file goes
              // through the system share sheet instead.
              logFilePath: _useMobileShell ? _diagnostics.log.filePath : null,
              onQuitRequested: _useMobileShell ? null : _shutDownAndExit,
              useMobileDictationSurface: _useMobileShell,
              modelProvisioner: _modelProvisioner,
              microphonePermissionWarmUp: _useMobileShell
                  ? warmUpMicrophonePermission
                  : null,
              floatingMicController: _floatingMicController,
              languageOptions: _useMobileShell
                  ? androidSpeechLanguageOptions
                  : speechLanguageOptions,
              // Noise suppression runs in-process on every platform now.
              showNoiseSuppression: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Deletes leftover dictation WAVs. Recordings are deleted right after
/// transcription; this catches files stranded by crashes or older builds.
Future<void> purgeStaleRecordings(Directory directory) async {
  // Synchronous IO on purpose: async file IO never completes inside the
  // widget-test fake-async zone, and this runs once at startup.
  if (!directory.existsSync()) {
    return;
  }
  for (final entry in directory.listSync()) {
    if (entry is File && entry.path.toLowerCase().endsWith('.wav')) {
      try {
        entry.deleteSync();
      } catch (_) {
        // A file still locked by a recorder is picked up next launch.
      }
    }
  }
}

PlatformBridge createDefaultPlatformBridge({
  bool? isWindows,
  bool? isLinux,
  bool? isMacOS,
  bool? isAndroid,
}) {
  if (isAndroid ?? Platform.isAndroid) {
    return AndroidPlatformBridge();
  }
  if (isWindows ?? Platform.isWindows) {
    return WindowsPlatformBridge();
  }
  if (isLinux ?? Platform.isLinux) {
    final xdotool = resolveXdotool();
    return LinuxPlatformBridge(
      xdotoolExecutable: xdotool.executable,
      xdotoolLibraryDirectory: xdotool.libraryDirectory,
      overlayExecutable: resolveBundledTool(
        bundledRelativePath: 'bin/overlay/typemate-overlay',
        fallbackCommand: '',
        environmentOverrideVariable: 'TYPEMATE_OVERLAY',
      ),
    );
  }
  if (isMacOS ?? Platform.isMacOS) {
    return MacosPlatformBridge();
  }

  return MockPlatformBridge();
}

HoldShortcutRegistrar createDefaultHoldShortcutRegistrar({
  bool? isWindows,
  bool? isLinux,
  bool? isMacOS,
}) {
  if (isWindows ?? Platform.isWindows) {
    return WindowsPollingHoldShortcutRegistrar();
  }
  if (isLinux ?? Platform.isLinux) {
    return LinuxX11HoldShortcutRegistrar();
  }
  if (isMacOS ?? Platform.isMacOS) {
    return MacosPollingHoldShortcutRegistrar();
  }

  return const NoopHoldShortcutRegistrar();
}

MicrophoneDiscovery createDefaultMicrophoneDiscovery({
  bool? isWindows,
  bool? isLinux,
  bool? isAndroid,
}) {
  // Windows uses the record plugin's MediaFoundation backend: built into
  // Windows 10/11, so microphone discovery needs no external binaries.
  if (isWindows ?? Platform.isWindows) {
    return RecordPackageMicrophoneDiscovery();
  }
  // Linux and Android record from the system default input, which the OS
  // routes to whichever microphone is active; the picker offers one entry.
  if ((isLinux ?? Platform.isLinux) || (isAndroid ?? Platform.isAndroid)) {
    return const SystemDefaultMicrophoneDiscovery();
  }

  // macOS and anything else: the record plugin captures natively there too.
  return RecordPackageMicrophoneDiscovery();
}

AudioRecorderFactory createDefaultAudioRecorderFactory({
  required Directory outputDirectory,
  bool? isWindows,
  bool? isLinux,
  bool? isAndroid,
}) {
  if (isWindows ?? Platform.isWindows) {
    return RecordPackageAudioRecorderFactory(outputDirectory: outputDirectory);
  }
  if (isAndroid ?? Platform.isAndroid) {
    // Android records the system default input (device selection is an OS
    // concern) and must request the runtime microphone permission before
    // the first capture.
    return RecordPackageAudioRecorderFactory(
      outputDirectory: outputDirectory,
      useSystemDefaultDevice: true,
      requestPermission: true,
    );
  }
  if (isLinux ?? Platform.isLinux) {
    // Linux records through ffmpeg's Pulse input; the binary comes from the
    // distro (documented dependency), an env override, or PATH.
    return MicrophoneAudioRecorderFactory.linux(
      outputDirectory: outputDirectory,
      ffmpegExecutable: resolveFfmpegExecutable(),
    );
  }
  return RecordPackageAudioRecorderFactory(outputDirectory: outputDirectory);
}

HoldShortcutSettingsStore createDefaultHoldShortcutSettingsStore({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return FileHoldShortcutSettingsStore(
    file: File('${base.path}/shortcut-settings.json'),
  );
}

MicrophoneSettingsStore createDefaultMicrophoneSettingsStore({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return FileMicrophoneSettingsStore(file: File('${base.path}/settings.json'));
}

DictationHistoryStore createDefaultDictationHistoryStore({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return FileDictationHistoryStore(file: File('${base.path}/history.json'));
}

SpeechSettingsStore createDefaultSpeechSettingsStore({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return FileSpeechSettingsStore(
    file: File('${base.path}/speech-settings.json'),
  );
}

/// The local troubleshooting log, next to the other per-user data so
/// "Open log folder" from Settings lands in a familiar place.
DiagnosticLog createDefaultDiagnosticLog({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return DiagnosticLog(file: File('${base.path}/logs/typemate.log'));
}

TelemetrySettingsStore createDefaultTelemetrySettingsStore({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return FileTelemetrySettingsStore(
    file: File('${base.path}/telemetry-settings.json'),
  );
}

/// Where dictation WAVs live between capture and transcription. Anchored to
/// the per-user data directory because the process CWD is unreliable: an
/// autostart launch via the HKCU Run key inherited C:\Windows\System32,
/// where the old CWD-relative build/recordings could not be created and
/// every dictation aborted the moment the shortcut was pressed.
Directory createDefaultRecordingsDirectory({
  Map<String, String>? environment,
  Directory? directory,
}) {
  final base = directory ?? _typeMateDataDirectory(environment: environment);
  return Directory('${base.path}/recordings');
}

Directory _typeMateDataDirectory({Map<String, String>? environment}) {
  final values = environment ?? Platform.environment;
  final appData = values['APPDATA']?.trim() ?? '';
  if (appData.isNotEmpty) {
    return Directory('$appData/TypeMate');
  }
  // Linux/macOS: XDG config home, matching where autostart entries live.
  final xdgConfigHome = values['XDG_CONFIG_HOME']?.trim() ?? '';
  if (xdgConfigHome.isNotEmpty) {
    return Directory('$xdgConfigHome/TypeMate');
  }
  final home = values['HOME']?.trim() ?? '';
  if (home.isNotEmpty) {
    return Directory('$home/.config/TypeMate');
  }
  return Directory('build/settings/TypeMate');
}

// Optional noise suppression: the GTCRN speech-enhancement model, run
// in-process through the sherpa_onnx plugin per recording when the
// Settings toggle is on.
const bundledGtcrnModelRelativePath = 'models/gtcrn_simple.onnx';

/// Creates the noise-suppression step, or null when its model is not
/// present. Unlike the speech runtimes this never throws: noise
/// suppression is an enhancement, and dictation must keep working on the
/// raw recording when the optional GTCRN model is missing.
AudioDenoiser? createDefaultAudioDenoiser({
  Map<String, String>? environment,
  PathExists? pathExists,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
}) {
  final values = environment ?? Platform.environment;
  final exists = pathExists ?? (path) => File(path).existsSync();
  final searchDirectories = [
    currentDirectoryPath ?? Directory.current.path,
    executableDirectoryPath ?? File(Platform.resolvedExecutable).parent.path,
  ];

  String? resolveOptional(String relativePath, String? environmentValue) {
    final override = environmentValue?.trim() ?? '';
    if (override.isNotEmpty) {
      return override;
    }
    for (final directory in searchDirectories) {
      final candidate = '${directory.replaceAll('\\', '/')}/$relativePath';
      if (exists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  final modelPath = resolveOptional(
    bundledGtcrnModelRelativePath,
    values['TYPEMATE_DENOISER_MODEL'],
  );
  if (modelPath == null) {
    debugPrint(
      'TypeMate: noise suppression model is missing; recordings are '
      'transcribed as captured. Run: dart run tool/fetch_whisper_runtime.dart',
    );
    return null;
  }
  return SherpaGtcrnAudioDenoiser(modelPath: modelPath);
}

/// Resolves a helper tool: env override, then the copy bundled next to the
/// app, then the bare name from PATH. Unlike the speech runtimes this never
/// throws — a missing tool surfaces as an actionable in-app error instead
/// of a crash.
String resolveBundledTool({
  required String bundledRelativePath,
  required String fallbackCommand,
  String? environmentOverrideVariable,
  Map<String, String>? environment,
  PathExists? pathExists,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
}) {
  final values = environment ?? Platform.environment;
  if (environmentOverrideVariable != null) {
    final override = values[environmentOverrideVariable]?.trim() ?? '';
    if (override.isNotEmpty) {
      return override;
    }
  }
  final exists = pathExists ?? (path) => File(path).existsSync();
  final searchDirectories = [
    currentDirectoryPath ?? Directory.current.path,
    executableDirectoryPath ?? File(Platform.resolvedExecutable).parent.path,
  ];
  for (final directory in searchDirectories) {
    final candidate = '${directory.replaceAll('\\', '/')}/$bundledRelativePath';
    if (exists(candidate)) {
      return candidate;
    }
  }
  return fallbackCommand;
}

String resolveFfmpegExecutable({
  Map<String, String>? environment,
  PathExists? pathExists,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
  bool? isWindows,
}) => resolveBundledTool(
  bundledRelativePath: platformExecutablePath(
    'bin/ffmpeg/ffmpeg',
    isWindows: isWindows,
  ),
  fallbackCommand: 'ffmpeg',
  environmentOverrideVariable: 'TYPEMATE_FFMPEG',
  environment: environment,
  pathExists: pathExists,
  currentDirectoryPath: currentDirectoryPath,
  executableDirectoryPath: executableDirectoryPath,
);

/// The bundled xdotool and the directory holding its private libxdo, or a
/// PATH fallback with no library override.
({String executable, String? libraryDirectory}) resolveXdotool({
  Map<String, String>? environment,
  PathExists? pathExists,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
}) {
  final executable = resolveBundledTool(
    bundledRelativePath: 'bin/xdotool/xdotool',
    fallbackCommand: 'xdotool',
    environmentOverrideVariable: 'TYPEMATE_XDOTOOL',
    environment: environment,
    pathExists: pathExists,
    currentDirectoryPath: currentDirectoryPath,
    executableDirectoryPath: executableDirectoryPath,
  );
  if (executable == 'xdotool') {
    return (executable: executable, libraryDirectory: null);
  }
  final libraryDirectory = executable.substring(0, executable.lastIndexOf('/'));
  return (executable: executable, libraryDirectory: libraryDirectory);
}
