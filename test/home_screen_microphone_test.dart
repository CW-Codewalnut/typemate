import 'package:dictation_flow/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:dictation_flow/src/core/dictation_controller.dart';
import 'package:dictation_flow/src/core/microphone_settings_controller.dart';
import 'package:dictation_flow/src/audio/mock_audio_recorder.dart';
import 'package:dictation_flow/src/platform/mock_platform_bridge.dart';
import 'package:dictation_flow/src/stt/mock_stt_engine.dart';
import 'package:dictation_flow/src/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows discovered microphones in settings panel', (tester) async {
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorder: MockAudioRecorder(),
    );
    final microphoneController = MicrophoneSettingsController(
      discovery: FakeMicrophoneDiscovery([
        const MicrophoneDevice(name: 'Microphone (Brio 100)'),
        const MicrophoneDevice(name: 'Headset (Tribit XSound Go)'),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          microphoneController: microphoneController,
        ),
      ),
    );

    await tester.tap(find.text('Refresh microphones'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone selection'), findsOneWidget);
    expect(find.text('Microphone (Brio 100)'), findsWidgets);
    expect(find.text('Headset (Tribit XSound Go)'), findsOneWidget);
    expect(find.text('2 microphones found.'), findsOneWidget);
  });
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  FakeMicrophoneDiscovery(this.devices);

  final List<MicrophoneDevice> devices;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => devices;
}
