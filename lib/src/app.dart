import 'package:flutter/material.dart';

import 'audio/ffmpeg_microphone_discovery.dart';
import 'audio/mock_audio_recorder.dart';
import 'core/dictation_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'platform/mock_platform_bridge.dart';
import 'stt/mock_stt_engine.dart';
import 'ui/home_screen.dart';

class DictationFlowApp extends StatefulWidget {
  const DictationFlowApp({super.key});

  @override
  State<DictationFlowApp> createState() => _DictationFlowAppState();
}

class _DictationFlowAppState extends State<DictationFlowApp> {
  late final DictationController controller;
  late final MicrophoneSettingsController microphoneController;

  @override
  void initState() {
    super.initState();
    controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorder: MockAudioRecorder(),
    );
    microphoneController = MicrophoneSettingsController(
      discovery: const FfmpegMicrophoneDiscovery(),
    );
  }

  @override
  void dispose() {
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
      ),
    );
  }
}
