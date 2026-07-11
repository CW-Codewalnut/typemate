import 'dart:io';

import 'package:flutter/material.dart';

import 'audio/ffmpeg_microphone_discovery.dart';
import 'audio/microphone_audio_recorder_factory.dart';
import 'core/dictation_controller.dart';
import 'core/hold_shortcut_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'core/microphone_settings_store.dart';
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
  late final MicrophoneSettingsController microphoneController;
  late final HoldShortcutController shortcutController;

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
    controller = DictationController(
      platformBridge: createDefaultPlatformBridge(),
      sttEngine: createDefaultSttEngine(),
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
    );
    shortcutController.register();
  }

  @override
  void dispose() {
    shortcutController.dispose();
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
        microphoneController: microphoneController,
        shortcutController: shortcutController,
      ),
    );
  }
}

PlatformBridge createDefaultPlatformBridge({bool? isWindows}) {
  if (isWindows ?? Platform.isWindows) {
    return const WindowsClipboardPastePlatformBridge();
  }

  return MockPlatformBridge();
}

HoldShortcutRegistrar createDefaultHoldShortcutRegistrar({bool? isWindows}) {
  if (isWindows ?? Platform.isWindows) {
    return WindowsPollingHoldShortcutRegistrar();
  }

  return const NoopHoldShortcutRegistrar();
}

MicrophoneSettingsStore createDefaultMicrophoneSettingsStore({
  Map<String, String>? environment,
}) {
  final values = environment ?? Platform.environment;
  final baseDirectory = values['APPDATA']?.trim().isNotEmpty == true
      ? Directory(values['APPDATA']!.trim())
      : Directory('build/settings');

  return FileMicrophoneSettingsStore(
    file: File('${baseDirectory.path}/TypeMate/settings.json'),
  );
}

SttEngine createDefaultSttEngine({Map<String, String>? environment}) {
  final values = environment ?? Platform.environment;
  final executable = values['TYPEMATE_WHISPER_CLI']?.trim() ?? '';
  final modelPath = values['TYPEMATE_WHISPER_MODEL']?.trim() ?? '';

  if (executable.isEmpty || modelPath.isEmpty) {
    return MockSttEngine();
  }

  return WhisperCliSttEngine(executable: executable, modelPath: modelPath);
}
