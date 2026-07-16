import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'components/app_scroll_behavior.dart';
import 'components/splash_screen.dart';
import 'core/audio/ffmpeg_microphone_discovery.dart';
import 'core/audio/microphone_audio_recorder_factory.dart';
import 'core/dictation_controller.dart';
import 'core/dictation_history_controller.dart';
import 'core/hold_shortcut_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'core/microphone_settings_store.dart';
import 'core/speech_settings_controller.dart';
import 'core/platform/mock_platform_bridge.dart';
import 'core/platform/platform_bridge.dart';
import 'core/platform/windows_platform_bridge.dart';
import 'core/platform/windows_polling_hold_shortcut_registrar.dart';
import 'core/stt/language_routing_stt_engine.dart';
import 'core/stt/parakeet_server_stt_engine.dart';
import 'core/stt/stt_engine.dart';
import 'core/stt/whisper_cli_stt_engine.dart';
import 'core/stt/whisper_server_stt_engine.dart';
import 'features/home/home_screen.dart';

class DictationFlowApp extends StatefulWidget {
  const DictationFlowApp({
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
  State<DictationFlowApp> createState() => _DictationFlowAppState();
}

class _DictationFlowAppState extends State<DictationFlowApp> {
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
    final recorderFactory = MicrophoneAudioRecorderFactory.windows(
      outputDirectory: Directory('build/recordings'),
    );
    microphoneController = MicrophoneSettingsController(
      discovery:
          widget.microphoneDiscovery ?? const FfmpegMicrophoneDiscovery(),
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
      title: 'Type Mate',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6CFF)),
        fontFamilyFallback: const [
          'Nirmala UI',
          'Nirmala Text',
          'Segoe UI',
          'Segoe UI Historic',
          'Segoe UI Symbol',
          'Arial Unicode MS',
          'Mangal',
          'Utsaah',
          'Aparajita',
          'Kokila',
          'Nirmala UI Semilight',
          'Vrinda',
          'Raavi',
          'Ebrima',
          'Gadugi',
          'Leelawadee UI',
          'Javanese Text',
          'Myanmar Text',
          'Mongolian Baiti',
          'Microsoft Himalaya',
          'Microsoft Yi Baiti',
          'Sylfaen',
          'Microsoft YaHei',
          'Microsoft JhengHei',
          'SimSun',
          'NSimSun',
          'Meiryo',
          'Malgun Gothic',
        ],
        useMaterial3: true,
      ),
      home: AnimatedSwitcher(
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
    );
  }
}

PlatformBridge createDefaultPlatformBridge({bool? isWindows}) {
  if (isWindows ?? Platform.isWindows) {
    return WindowsPlatformBridge();
  }

  return MockPlatformBridge();
}

HoldShortcutRegistrar createDefaultHoldShortcutRegistrar({bool? isWindows}) {
  if (isWindows ?? Platform.isWindows) {
    return WindowsPollingHoldShortcutRegistrar();
  }

  return const NoopHoldShortcutRegistrar();
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
  final baseDirectory = values['APPDATA']?.trim().isNotEmpty == true
      ? Directory(values['APPDATA']!.trim())
      : Directory('build/settings');

  return Directory('${baseDirectory.path}/TypeMate');
}

typedef PathExists = bool Function(String path);

const bundledWhisperCliRelativePath = 'bin/whisper/whisper-cli.exe';
const bundledWhisperServerRelativePath = 'bin/whisper/whisper-server.exe';
// Hindi uses the Vaani small fine-tune; Hinglish the base-sized Oriserve
// Swift fine-tune. Each runs on its own resident whisper server, but only
// the selected language's server is kept loaded (RAM policy).
const bundledHindiWhisperModelRelativePath =
    'models/ggml-small-vaani-hindi-q6.bin';
const bundledHinglishWhisperModelRelativePath =
    'models/ggml-hindi2hinglish-swift.bin';
const hindiServerPort = 43008;
const hinglishServerPort = 43009;
const _hindiDevanagariPrompt =
    'हिंदी भाषण को देवनागरी लिपि में ठीक-ठीक लिखें। '
    'अंग्रेज़ी में अनुवाद न करें।';
// Silero VAD trims hold-to-talk silence before decoding; without it whisper
// loops and repeats sentences while decoding the silent tail.
const bundledVadModelRelativePath = 'models/ggml-silero-v5.1.2.bin';
// English runs on a resident sherpa-onnx server with NVIDIA Parakeet TDT
// 0.6B v3: the model loads once at app start, then each utterance decodes
// in about a second with the best accuracy of every model benchmarked.
const bundledSherpaServerRelativePath =
    'bin/sherpa/sherpa-onnx-offline-websocket-server.exe';
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

  final hindi = WhisperServerSttEngine(
    serverExecutable: whisperServer,
    modelPath: resolve(bundledHindiWhisperModelRelativePath),
    vadModelPath: vadModel,
    cliLanguage: 'hi',
    prompt: _hindiDevanagariPrompt,
    port: hindiServerPort,
  );

  final hinglish = WhisperServerSttEngine(
    serverExecutable: whisperServer,
    modelPath: resolve(bundledHinglishWhisperModelRelativePath),
    vadModelPath: vadModel,
    // The Hinglish fine-tune decodes as Hindi and romanizes on its own; a
    // script prompt would fight it.
    cliLanguage: 'hi',
    port: hinglishServerPort,
  );

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
      'hinglish': hinglish,
    },
    fallback: hindi,
    languageCodeProvider: languageCodeProvider ?? (() => 'en'),
  );
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
