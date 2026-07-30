import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'components/app_scroll_behavior.dart';
import 'components/splash_screen.dart';
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
import 'core/platform/linux/linux_platform_bridge.dart';
import 'core/platform/linux/linux_x11_hold_shortcut_registrar.dart';
import 'core/platform/macos/macos_platform_bridge.dart';
import 'core/platform/macos/macos_polling_hold_shortcut_registrar.dart';
import 'core/platform/mock_platform_bridge.dart';
import 'core/platform/platform_bridge.dart';
import 'core/platform/windows/windows_platform_bridge.dart';
import 'core/platform/windows/windows_polling_hold_shortcut_registrar.dart';
import 'core/stt/android_speech_runtime.dart';
import 'core/stt/language_routing_stt_engine.dart';
import 'core/stt/parakeet_server_stt_engine.dart';
import 'core/stt/stt_engine.dart';
import 'core/stt/stt_model_provisioner.dart';
import 'core/stt/whisper_cli_stt_engine.dart';
import 'core/stt/whisper_server_stt_engine.dart';
import 'features/home/home_screen.dart';
import 'models/app_identity.dart';
import 'theme/app_theme.dart';

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
    this.splashDuration = const Duration(milliseconds: 900),
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
  final Duration splashDuration;

  /// Mobile experience: in-app dictation tab, no window title bar, no
  /// shortcut/quit/noise-suppression settings, Parakeet-only languages.
  /// Defaults to the platform (Android); tests can force it on desktop.
  final bool? useMobileShell;

  /// Overrides the speech model download state; tests pair it with a mock
  /// [sttEngine].
  final SttModelProvisioner? modelProvisioner;

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
  SttModelProvisioner? _modelProvisioner;
  late bool _showSplash;
  late String _lastPreparedLanguageCode;
  AudioDenoiser? _audioDenoiser;

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.diagnosticReporter ?? DiagnosticReporter();
    _useMobileShell = widget.useMobileShell ?? Platform.isAndroid;
    _showSplash = widget.splashDuration > Duration.zero;
    if (_showSplash) {
      Timer(widget.splashDuration, () {
        if (mounted) {
          setState(() => _showSplash = false);
        }
      });
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
    } else {
      _sttEngine = createDefaultSttEngine(
        languageCodeProvider: () => speechSettingsController.languageCode,
        diagnostics: _diagnostics,
      );
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
    unawaited(
      _sttEngine.prepare().catchError((_) {
        // Preloading is best-effort; a failure surfaces on the next
        // dictation with a proper error state.
      }),
    );
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _showSplash
                  ? const SplashScreen()
                  : HomeScreen(
                      controller: controller,
                      historyController: historyController,
                      microphoneController: microphoneController,
                      speechSettingsController: speechSettingsController,
                      // Mobile hides every desktop-only Settings surface:
                      // no global shortcut, no file-manager log folder, no
                      // Quit (Android lifecycles apps itself).
                      shortcutController: _useMobileShell
                          ? null
                          : shortcutController,
                      telemetryController: widget.telemetryController,
                      logsDirectoryPath: _useMobileShell
                          ? null
                          : _diagnostics.log.directoryPath,
                      onQuitRequested: _useMobileShell
                          ? null
                          : _shutDownAndExit,
                      showDictationTab: _useMobileShell,
                      modelProvisioner: _modelProvisioner,
                      microphonePermissionWarmUp: _useMobileShell
                          ? warmUpMicrophonePermission
                          : null,
                      languageOptions: _useMobileShell
                          ? androidSpeechLanguageOptions
                          : speechLanguageOptions,
                      showNoiseSuppression: !_useMobileShell,
                    ),
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

typedef PathExists = bool Function(String path);

/// Appends the Windows executable suffix; Linux binaries have none.
String platformExecutablePath(String path, {bool? isWindows}) =>
    (isWindows ?? Platform.isWindows) ? '$path.exe' : path;

final bundledWhisperCliRelativePath = platformExecutablePath(
  'bin/whisper/whisper-cli',
);
final bundledWhisperServerRelativePath = platformExecutablePath(
  'bin/whisper/whisper-server',
);
const hindiServerPort = 43008;
const hinglishServerPort = 43009;
const _hindiDevanagariPrompt =
    'हिंदी भाषण को देवनागरी लिपि में ठीक-ठीक लिखें। '
    'अंग्रेज़ी में अनुवाद न करें।';

/// A language served by its own resident whisper.cpp HTTP server. Only the
/// selected language's server is kept loaded (RAM policy). Ports are fixed
/// per language so an orphaned server from an unclean exit is adopted
/// rather than duplicated.
class WhisperServerLanguage {
  const WhisperServerLanguage({
    required this.code,
    required this.modelRelativePath,
    required this.port,
    this.cliLanguage,
    this.prompt,
  });

  final String code;
  final String modelRelativePath;
  final int port;

  /// Whisper's language flag when it differs from [code] (e.g. Hinglish
  /// decodes as Hindi and romanizes on its own).
  final String? cliLanguage;
  final String? prompt;
}

const whisperServerLanguages = [
  // Vaani small fine-tune, noise-robust Devanagari output.
  WhisperServerLanguage(
    code: 'hi',
    modelRelativePath: 'models/ggml-small-vaani-hindi-q6.bin',
    port: hindiServerPort,
    prompt: _hindiDevanagariPrompt,
  ),
  // Oriserve Swift fine-tune, base-sized, romanized output; a script
  // prompt would fight it.
  WhisperServerLanguage(
    code: 'hinglish',
    modelRelativePath: 'models/ggml-hindi2hinglish-swift.bin',
    port: hinglishServerPort,
    cliLanguage: 'hi',
  ),
  // Vistaar (AI4Bharat) per-language fine-tunes, small-sized, quantized to
  // q5_0 by this repo (hosted on the models-v1 GitHub release).
  WhisperServerLanguage(
    code: 'ta',
    modelRelativePath: 'models/ggml-vistaar-tamil-small-q5_0.bin',
    port: 43011,
  ),
  // Telugu, Kannada, and Gujarati are intentionally absent: their Vistaar
  // checkpoints decode non-deterministically (thin logit margins flip
  // tokens into hallucinations run-to-run, at any quantization level and
  // even fp16), failing the "visible languages must work" bar. Marathi
  // validated cleanly but was cut for install size: its only checkpoint is
  // medium-sized (~514 MB, kept at R:/Models/whisper and on the models-v1
  // release for an easy re-add).
];
// Silero VAD trims hold-to-talk silence before decoding; without it whisper
// loops and repeats sentences while decoding the silent tail.
const bundledVadModelRelativePath = 'models/ggml-silero-v5.1.2.bin';
// English runs on a resident sherpa-onnx server with NVIDIA Parakeet TDT
// 0.6B v3: the model loads once at app start, then each utterance decodes
// in about a second with the best accuracy of every model benchmarked.
final bundledSherpaServerRelativePath = platformExecutablePath(
  'bin/sherpa/sherpa-onnx-offline-websocket-server',
);
const bundledParakeetDirRelativePath = 'models/parakeet-tdt-0.6b-v3-int8';
// Optional noise suppression: the sherpa-onnx offline denoiser (from the
// same archive as the websocket server) running the GTCRN
// speech-enhancement model, applied per recording when the Settings toggle
// is on.
final bundledDenoiserRelativePath = platformExecutablePath(
  'bin/sherpa/sherpa-onnx-offline-denoiser',
);
const bundledGtcrnModelRelativePath = 'models/gtcrn_simple.onnx';
// The 25 languages Parakeet TDT 0.6B v3 transcribes, with automatic
// language detection — every one routes to the same resident server.
const parakeetLanguageCodes = [
  'en', 'bg', 'hr', 'cs', 'da', 'nl', 'et', 'fi', 'fr', 'de', 'el', 'hu', //
  'it', 'lv', 'lt', 'mt', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'es', 'sv',
  'uk',
];

/// Creates the production STT engine backed by the runtimes that ship with
/// the app. Every file is required: a missing binary or model is an
/// installation defect and throws instead of degrading silently.
SttEngine createDefaultSttEngine({
  Map<String, String>? environment,
  PathExists? pathExists,
  SttLanguageCodeProvider? languageCodeProvider,
  DiagnosticReporter? diagnostics,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
}) {
  final values = environment ?? Platform.environment;
  final exists = pathExists ?? (path) => File(path).existsSync();
  final searchDirectories = [
    currentDirectoryPath ?? Directory.current.path,
    executableDirectoryPath ?? File(Platform.resolvedExecutable).parent.path,
  ];

  String resolve(String relativePath, {String? environmentValue}) =>
      _resolveRuntimeFile(
        environmentValue: environmentValue,
        relativePath: relativePath,
        searchDirectories: searchDirectories,
        exists: exists,
      );

  final whisperCli = resolve(
    bundledWhisperCliRelativePath,
    environmentValue: values['TYPEMATE_WHISPER_CLI'],
  );

  // An explicit model override applies to every language and bypasses the
  // Parakeet server entirely (power-user escape hatch).
  final envModelPath = values['TYPEMATE_WHISPER_MODEL']?.trim() ?? '';
  if (envModelPath.isNotEmpty) {
    return WhisperCliSttEngine(
      executable: whisperCli,
      modelPath: envModelPath,
      vadModelPath: resolve(bundledVadModelRelativePath),
      languageCodeProvider: languageCodeProvider,
    );
  }

  final whisperServer = resolve(bundledWhisperServerRelativePath);
  final vadModel = resolve(bundledVadModelRelativePath);

  final whisperEnginesByCode = {
    for (final language in whisperServerLanguages)
      language.code: WhisperServerSttEngine(
        serverExecutable: whisperServer,
        modelPath: resolve(language.modelRelativePath),
        vadModelPath: vadModel,
        cliLanguage: language.cliLanguage ?? language.code,
        prompt: language.prompt,
        port: language.port,
        diagnostics: diagnostics,
      ),
  };

  final parakeet = ParakeetServerSttEngine(
    serverExecutable: resolve(bundledSherpaServerRelativePath),
    encoderPath: resolve('$bundledParakeetDirRelativePath/encoder.int8.onnx'),
    decoderPath: resolve('$bundledParakeetDirRelativePath/decoder.int8.onnx'),
    joinerPath: resolve('$bundledParakeetDirRelativePath/joiner.int8.onnx'),
    tokensPath: resolve('$bundledParakeetDirRelativePath/tokens.txt'),
    diagnostics: diagnostics,
  );

  return LanguageRoutingSttEngine(
    routes: {
      for (final code in parakeetLanguageCodes) code: parakeet,
      ...whisperEnginesByCode,
    },
    fallback: whisperEnginesByCode['hi']!,
    languageCodeProvider: languageCodeProvider ?? (() => 'en'),
  );
}

/// Creates the noise-suppression step, or null when its runtime is not
/// present. Unlike the speech runtimes this never throws: noise
/// suppression is an enhancement, and dictation must keep working on the
/// raw recording when the optional denoiser is missing.
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

  final executable = resolveOptional(
    bundledDenoiserRelativePath,
    values['TYPEMATE_DENOISER'],
  );
  final modelPath = resolveOptional(
    bundledGtcrnModelRelativePath,
    values['TYPEMATE_DENOISER_MODEL'],
  );
  if (executable == null || modelPath == null) {
    debugPrint(
      'TypeMate: noise suppression runtime is missing; recordings are '
      'transcribed as captured. Run: dart run tool/fetch_whisper_runtime.dart',
    );
    return null;
  }
  return SherpaGtcrnAudioDenoiser(executable: executable, modelPath: modelPath);
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

String _resolveRuntimeFile({
  required String? environmentValue,
  required String relativePath,
  required List<String> searchDirectories,
  required PathExists exists,
}) {
  final override = environmentValue?.trim() ?? '';
  if (override.isNotEmpty) {
    return override;
  }

  final candidates = [
    for (final directory in searchDirectories)
      '${directory.replaceAll('\\', '/')}/$relativePath',
  ];
  for (final candidate in candidates) {
    if (exists(candidate)) {
      return candidate;
    }
  }

  throw SttRuntimeException(
    'TypeMate installation is broken: $relativePath was not found. '
    'Searched: ${candidates.join(', ')}. '
    'Reinstall the app or run: dart run tool/fetch_whisper_runtime.dart',
  );
}
