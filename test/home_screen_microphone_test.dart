import 'package:typemate/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/audio/mock_audio_recorder.dart';
import 'package:typemate/src/platform/mock_platform_bridge.dart';
import 'package:typemate/src/stt/mock_stt_engine.dart';
import 'package:typemate/src/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'automatically prepares the local speech engine when the shell opens',
    (tester) async {
      final sttEngine = MockSttEngine();
      final dictationController = DictationController(
        platformBridge: MockPlatformBridge(),
        sttEngine: sttEngine,
        audioRecorder: MockAudioRecorder(),
      );
      final microphoneController = MicrophoneSettingsController(
        discovery: FakeMicrophoneDiscovery(const []),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            controller: dictationController,
            microphoneController: microphoneController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(await sttEngine.isReady(), isTrue);
      expect(find.text('Ready. Hold the shortcut and speak.'), findsOneWidget);
    },
  );

  testWidgets('automatically scans microphones when the shell opens', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();

    expect(find.text('Microphone selection'), findsOneWidget);
    expect(find.text('Microphone (Brio 100)'), findsWidgets);
    expect(find.text('Headset (Tribit XSound Go)'), findsOneWidget);
    expect(find.text('2 microphones found.'), findsOneWidget);
  });

  testWidgets('disables dictation preview until a microphone is selected', (
    tester,
  ) async {
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorder: MockAudioRecorder(),
    );
    final microphoneController = MicrophoneSettingsController(
      discovery: FakeMicrophoneDiscovery(const []),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          microphoneController: microphoneController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hold shortcut preview'),
    );

    expect(find.text('No microphones found.'), findsOneWidget);
    expect(button.onPressed, isNull);
  });

  testWidgets('shows a microphone scanning error with recovery action', (
    tester,
  ) async {
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorder: MockAudioRecorder(),
    );
    final microphoneController = MicrophoneSettingsController(
      discovery: ThrowingMicrophoneDiscovery(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          microphoneController: microphoneController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Unable to scan microphones. Check FFmpeg and microphone permissions, then refresh.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Refresh microphones'), findsOneWidget);
  });

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
    await tester.pumpAndSettle();

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

class ThrowingMicrophoneDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    throw StateError('ffmpeg unavailable');
  }
}
