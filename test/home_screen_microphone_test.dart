import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/audio/mock_audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/dictation_history_controller.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';
import 'package:typemate/src/platform/mock_platform_bridge.dart';
import 'package:typemate/src/stt/mock_stt_engine.dart';
import 'package:typemate/src/stt/stt_engine.dart';
import 'package:typemate/src/ui/home_screen.dart';

void main() {
  testWidgets(
    'history home prepares the local speech engine when the shell opens',
    (tester) async {
      final sttEngine = MockSttEngine();
      await tester.pumpHome(sttEngine: sttEngine);

      expect(await sttEngine.isReady(), isTrue);
      expect(find.text('Speech history'), findsOneWidget);
      expect(find.text('Ready. Hold the shortcut and speak.'), findsOneWidget);
    },
  );

  testWidgets('settings page scans and shows microphones', (tester) async {
    await tester.pumpHome(
      microphoneDiscovery: FakeMicrophoneDiscovery([
        const MicrophoneDevice(name: 'Microphone (Brio 100)'),
        const MicrophoneDevice(name: 'Headset (Tribit XSound Go)'),
      ]),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Microphone (Brio 100)'), findsOneWidget);
    expect(find.text('2 microphones found.'), findsOneWidget);
  });

  testWidgets('disables dictation preview until a microphone is selected', (
    tester,
  ) async {
    await tester.pumpHome(
      microphoneDiscovery: FakeMicrophoneDiscovery(const []),
    );

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hold shortcut preview'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('No microphones found.'), findsOneWidget);
  });

  testWidgets('settings page shows a microphone scanning error', (
    tester,
  ) async {
    await tester.pumpHome(microphoneDiscovery: ThrowingMicrophoneDiscovery());

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Unable to scan microphones. Check FFmpeg and microphone permissions, then refresh.',
      ),
      findsOneWidget,
    );
    expect(find.text('Refresh microphones'), findsOneWidget);
  });

  testWidgets('settings page lets user choose language appropriate model', (
    tester,
  ) async {
    await tester.pumpHome();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hindi').last);
    await tester.pumpAndSettle();

    expect(find.text('Base Hindi'), findsOneWidget);
    expect(find.text('Hindi-focused local dictation model.'), findsOneWidget);
  });

  testWidgets('history page shows generated speech text', (tester) async {
    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript('Ship the local dictation flow.');
    await tester.pump();

    expect(find.text('Ship the local dictation flow.'), findsOneWidget);
  });
}

extension on WidgetTester {
  Future<void> pumpHome({
    SttEngine? sttEngine,
    MicrophoneDiscovery? microphoneDiscovery,
    DictationHistoryController? historyController,
  }) async {
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: sttEngine ?? MockSttEngine(),
      audioRecorder: MockAudioRecorder(),
      onTranscriptGenerated: historyController?.addTranscript,
    );
    final microphoneController = MicrophoneSettingsController(
      discovery: microphoneDiscovery ?? FakeMicrophoneDiscovery(const []),
    );

    await pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          historyController: historyController ?? DictationHistoryController(),
          microphoneController: microphoneController,
          speechSettingsController: SpeechSettingsController(),
        ),
      ),
    );
    await pump(const Duration(milliseconds: 250));
    await pump(const Duration(milliseconds: 250));
  }
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
