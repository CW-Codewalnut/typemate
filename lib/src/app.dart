import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'audio/ffmpeg_microphone_discovery.dart';
import 'audio/microphone_audio_recorder_factory.dart';
import 'core/dictation_controller.dart';
import 'core/dictation_history_controller.dart';
import 'core/hold_shortcut_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'core/microphone_settings_store.dart';
import 'core/speech_settings_controller.dart';
import 'platform/mock_platform_bridge.dart';
import 'platform/platform_bridge.dart';
import 'platform/windows_clipboard_paste_platform_bridge.dart';
import 'platform/windows_polling_hold_shortcut_registrar.dart';
import 'stt/mock_stt_engine.dart';
import 'stt/stt_engine.dart';
import 'stt/whisper_cli_stt_engine.dart';
import 'ui/home_screen.dart';

class DictationFlowApp extends StatefulWidget {
  const DictationFlowApp({
    super.key,
    this.microphoneDiscovery,
    this.holdShortcutRegistrar,
  });

  final MicrophoneDiscovery? microphoneDiscovery;
  final HoldShortcutRegistrar? holdShortcutRegistrar;

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

  @override
  void initState() {
    super.initState();
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
      sttEngine: createDefaultSttEngine(
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
      title: 'TypeMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6CFF)),
        useMaterial3: true,
      ),
      home: HomeScreen(
        controller: controller,
        historyController: historyController,
        microphoneController: microphoneController,
        speechSettingsController: speechSettingsController,
        shortcutController: shortcutController,
      ),
    );
  }
}

PlatformBridge createDefaultPlatformBridge({bool? isWindows}) {
  if (isWindows ?? Platform.isWindows) {
    return WindowsClipboardPastePlatformBridge();
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

const verifiedWhisperCliPath =
    'R:/Tools/whisper.cpp/v1.9.1-x64/Release/whisper-cli.exe';
const verifiedWhisperModelPath = 'R:/Models/whisper/ggml-base.bin';

SttEngine createDefaultSttEngine({
  Map<String, String>? environment,
  PathExists? pathExists,
  SttLanguageCodeProvider? languageCodeProvider,
}) {
  final values = environment ?? Platform.environment;
  final executable = values['TYPEMATE_WHISPER_CLI']?.trim() ?? '';
  final modelPath = values['TYPEMATE_WHISPER_MODEL']?.trim() ?? '';

  if (executable.isNotEmpty && modelPath.isNotEmpty) {
    return WhisperCliSttEngine(
      executable: executable,
      modelPath: modelPath,
      languageCodeProvider: languageCodeProvider,
    );
  }

  final exists = pathExists ?? (path) => File(path).existsSync();
  if (executable.isEmpty &&
      modelPath.isEmpty &&
      exists(verifiedWhisperCliPath) &&
      exists(verifiedWhisperModelPath)) {
    return WhisperCliSttEngine(
      executable: verifiedWhisperCliPath,
      modelPath: verifiedWhisperModelPath,
      languageCodeProvider: languageCodeProvider,
    );
  }

  return MockSttEngine();
}
