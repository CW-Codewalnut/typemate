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
import 'core/stt/stt_engine.dart';
import 'core/stt/whisper_cli_stt_engine.dart';
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
    controller = DictationController(
      platformBridge: platformBridge,
      sttEngine:
          widget.sttEngine ??
          createDefaultSttEngine(
            languageCodeProvider: () => speechSettingsController.languageCode,
          ),
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
  }

  @override
  void dispose() {
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
const bundledWhisperModelRelativePath = 'models/ggml-large-v3-turbo-q5_0.bin';
// English routes to a much faster model: on laptop CPUs `small` transcribes
// English as accurately as turbo at roughly a third of the latency, while
// Hindi and the other languages need turbo's accuracy.
const bundledEnglishWhisperModelRelativePath = 'models/ggml-small.bin';

/// Creates the production STT engine backed by the whisper runtime that
/// ships with the app. The runtime is required: a missing CLI or model is an
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

  final executable = _resolveRuntimeFile(
    environmentValue: values['TYPEMATE_WHISPER_CLI'],
    relativePath: bundledWhisperCliRelativePath,
    searchDirectories: searchDirectories,
    exists: exists,
  );
  final envModelPath = values['TYPEMATE_WHISPER_MODEL']?.trim() ?? '';
  final modelPath = _resolveRuntimeFile(
    environmentValue: envModelPath,
    relativePath: bundledWhisperModelRelativePath,
    searchDirectories: searchDirectories,
    exists: exists,
  );
  // An explicit model override applies to every language; otherwise English
  // routes to the bundled fast model.
  final englishModelPath = envModelPath.isNotEmpty
      ? null
      : _resolveRuntimeFile(
          environmentValue: null,
          relativePath: bundledEnglishWhisperModelRelativePath,
          searchDirectories: searchDirectories,
          exists: exists,
        );

  return WhisperCliSttEngine(
    executable: executable,
    modelPath: modelPath,
    modelPathOverridesByLanguage: englishModelPath == null
        ? const {}
        : {'en': englishModelPath},
    languageCodeProvider: languageCodeProvider,
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
