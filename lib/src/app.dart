import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'components/app_scroll_behavior.dart';
import 'components/splash_screen.dart';
import 'components/window_title_bar.dart';
import 'core/audio/microphone_discovery.dart';
import 'core/audio/microphone_audio_recorder_factory.dart';
import 'core/audio/system_default_microphone_discovery.dart';
import 'core/audio/record_package_audio.dart';
import 'core/dictation_controller.dart';
import 'core/dictation_history_controller.dart';
import 'core/hold_shortcut_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'core/microphone_settings_store.dart';
import 'core/speech_settings_controller.dart';
import 'core/platform/linux/linux_platform_bridge.dart';
import 'core/platform/linux/linux_x11_hold_shortcut_registrar.dart';
import 'core/platform/mock_platform_bridge.dart';
import 'core/platform/platform_bridge.dart';
import 'core/platform/windows/windows_platform_bridge.dart';
import 'core/platform/windows/windows_polling_hold_shortcut_registrar.dart';
import 'core/stt/language_routing_stt_engine.dart';
import 'core/stt/parakeet_server_stt_engine.dart';
import 'core/stt/stt_engine.dart';
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
    this.splashDuration = const Duration(milliseconds: 900),
  });

  final MicrophoneDiscovery? microphoneDiscovery;
  final HoldShortcutRegistrar? holdShortcutRegistrar;
  final SttEngine? sttEngine;
  final Duration splashDuration;

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
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.splashDuration > Duration.zero;
    if (_showSplash) {
      Timer(widget.splashDuration, () {
        if (mounted) {
          setState(() => _showSplash = false);
        }
      });
    }
    final recordingsDirectory = Directory('build/recordings');
    // Dictation audio is transcribe-and-delete; sweep anything a crash or
    // an older build left behind so no speech sits on disk.
    unawaited(purgeStaleRecordings(recordingsDirectory));
    final recorderFactory = createDefaultAudioRecorderFactory(
      outputDirectory: recordingsDirectory,
    );
    microphoneController = MicrophoneSettingsController(
      discovery:
          widget.microphoneDiscovery ?? createDefaultMicrophoneDiscovery(),
      store: createDefaultMicrophoneSettingsStore(),
    );
    historyController = DictationHistoryController(
      store: createDefaultDictationHistoryStore(),
    );
    speechSettingsController = SpeechSettingsController(
      store: createDefaultSpeechSettingsStore(),
    );
    platformBridge = createDefaultPlatformBridge();
    _sttEngine =
        widget.sttEngine ??
        createDefaultSttEngine(
          languageCodeProvider: () => speechSettingsController.languageCode,
        );
    if (platformBridge case final QuitRequestSource quitSource) {
      quitSource.onQuitRequested = _shutDownAndExit;
    }
    controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: _sttEngine,
      onTranscriptGenerated: historyController.addTranscript,
      audioRecorderProvider: () {
        final selectedMicrophone = microphoneController.selectedMicrophone;
        if (selectedMicrophone == null) {
          return null;
        }

        return recorderFactory.create(selectedMicrophone);
      },
    );
    shortcutController = HoldShortcutController(
      dictationController: controller,
      registrar:
          widget.holdShortcutRegistrar ?? createDefaultHoldShortcutRegistrar(),
      store: createDefaultHoldShortcutSettingsStore(),
    );
    shortcutController.register();
    unawaited(platformBridge.ensureLaunchAtStartup());
    historyController.load();
    speechSettingsController.load();
    // Swap resident speech servers as soon as the language changes so the
    // newly selected model is warm before the next dictation, and the old
    // one's RAM is released.
    speechSettingsController.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
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
          const WindowTitleBar(),
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
                      shortcutController: shortcutController,
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

PlatformBridge createDefaultPlatformBridge({bool? isWindows, bool? isLinux}) {
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

  return MockPlatformBridge();
}

HoldShortcutRegistrar createDefaultHoldShortcutRegistrar({
  bool? isWindows,
  bool? isLinux,
}) {
  if (isWindows ?? Platform.isWindows) {
    return WindowsPollingHoldShortcutRegistrar();
  }
  if (isLinux ?? Platform.isLinux) {
    return LinuxX11HoldShortcutRegistrar();
  }

  return const NoopHoldShortcutRegistrar();
}

MicrophoneDiscovery createDefaultMicrophoneDiscovery({
  bool? isWindows,
  bool? isLinux,
}) {
  // Windows uses the record plugin's MediaFoundation backend: built into
  // Windows 10/11, so microphone discovery needs no external binaries.
  if (isWindows ?? Platform.isWindows) {
    return RecordPackageMicrophoneDiscovery();
  }
  if (isLinux ?? Platform.isLinux) {
    return const SystemDefaultMicrophoneDiscovery();
  }

  // macOS and anything else: the record plugin captures natively there too.
  return RecordPackageMicrophoneDiscovery();
}

AudioRecorderFactory createDefaultAudioRecorderFactory({
  required Directory outputDirectory,
  bool? isWindows,
}) {
  if (isWindows ?? Platform.isWindows) {
    return RecordPackageAudioRecorderFactory(outputDirectory: outputDirectory);
  }
  if (Platform.isLinux) {
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
}) {
  return FileHoldShortcutSettingsStore(
    file: File(
      '${_typeMateDataDirectory(environment: environment).path}/shortcut-settings.json',
    ),
  );
}

MicrophoneSettingsStore createDefaultMicrophoneSettingsStore({
  Map<String, String>? environment,
}) {
  return FileMicrophoneSettingsStore(
    file: File(
      '${_typeMateDataDirectory(environment: environment).path}/settings.json',
    ),
  );
}

DictationHistoryStore createDefaultDictationHistoryStore({
  Map<String, String>? environment,
}) {
  return FileDictationHistoryStore(
    file: File(
      '${_typeMateDataDirectory(environment: environment).path}/history.json',
    ),
  );
}

SpeechSettingsStore createDefaultSpeechSettingsStore({
  Map<String, String>? environment,
}) {
  return FileSpeechSettingsStore(
    file: File(
      '${_typeMateDataDirectory(environment: environment).path}/speech-settings.json',
    ),
  );
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
      ),
  };

  final parakeet = ParakeetServerSttEngine(
    serverExecutable: resolve(bundledSherpaServerRelativePath),
    encoderPath: resolve('$bundledParakeetDirRelativePath/encoder.int8.onnx'),
    decoderPath: resolve('$bundledParakeetDirRelativePath/decoder.int8.onnx'),
    joinerPath: resolve('$bundledParakeetDirRelativePath/joiner.int8.onnx'),
    tokensPath: resolve('$bundledParakeetDirRelativePath/tokens.txt'),
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
