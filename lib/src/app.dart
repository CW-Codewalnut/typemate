import 'dart:io';

import 'package:flutter/material.dart';

import 'audio/ffmpeg_microphone_discovery.dart';
import 'audio/microphone_audio_recorder_factory.dart';
import 'core/dictation_controller.dart';
import 'core/microphone_settings_controller.dart';
import 'platform/mock_platform_bridge.dart';
import 'stt/mock_stt_engine.dart';
import 'ui/home_screen.dart';

class DictationFlowApp extends StatefulWidget {
  const DictationFlowApp({super.key, this.microphoneDiscovery});

  final MicrophoneDiscovery? microphoneDiscovery;

  @override
  State<DictationFlowApp> createState() => _DictationFlowAppState();
}

class _DictationFlowAppState extends State<DictationFlowApp> {
  late final DictationController controller;
  late final MicrophoneSettingsController microphoneController;

  @override
  void initState() {
    super.initState();
    final recorderFactory = MicrophoneAudioRecorderFactory.windows(
      outputDirectory: Directory('build/recordings'),
    );
    microphoneController = MicrophoneSettingsController(
      discovery:
          widget.microphoneDiscovery ?? const FfmpegMicrophoneDiscovery(),
    );
    controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorderProvider: () {
        final selectedMicrophone = microphoneController.selectedMicrophone;
        if (selectedMicrophone == null) {
          return null;
        }

        return recorderFactory.create(selectedMicrophone);
      },
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
