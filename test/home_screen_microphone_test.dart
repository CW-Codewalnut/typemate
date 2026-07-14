import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/audio/audio_recorder.dart';
import 'package:typemate/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/audio/mock_audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/dictation_history_controller.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
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
      await tester.pumpHome(
        sttEngine: sttEngine,
        includeShortcutController: true,
      );

      expect(await sttEngine.isReady(), isTrue);
      expect(find.text('Speech history'), findsOneWidget);
      expect(
        find.text('Press and hold Win+Alt and start speaking.'),
        findsOneWidget,
      );
      expect(find.text('Ready. Hold the shortcut and speak.'), findsNothing);
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

  testWidgets('history page does not show a shortcut preview button', (
    tester,
  ) async {
    await tester.pumpHome(
      microphoneDiscovery: FakeMicrophoneDiscovery(const []),
    );

    expect(find.text('Hold shortcut preview'), findsNothing);
    expect(find.text('Release shortcut preview'), findsNothing);

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

  testWidgets('settings page wires language selection to Whisper.cpp', (
    tester,
  ) async {
    final speechSettingsController = SpeechSettingsController();
    await tester.pumpHome(speechSettingsController: speechSettingsController);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Speech recognition'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.textContaining('Model:'), findsNothing);
    expect(find.textContaining('Whisper.cpp'), findsNothing);

    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 20 && find.text('Hindi').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -360));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Hindi').last);
    await tester.pumpAndSettle();

    expect(speechSettingsController.languageCode, 'hi');
  });

  testWidgets('history page shows generated speech text', (tester) async {
    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript('Ship the local dictation flow.');
    await tester.pump();

    expect(find.text('Ship the local dictation flow.'), findsOneWidget);
  });

  testWidgets('top animation appears while listening and transcribing', (
    tester,
  ) async {
    final sttEngine = HoldingSttEngine();
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: sttEngine,
      audioRecorder: ImmediateAudioRecorder(),
    );
    final microphoneController = MicrophoneSettingsController(
      discovery: FakeMicrophoneDiscovery(const []),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          historyController: DictationHistoryController(),
          microphoneController: microphoneController,
          speechSettingsController: SpeechSettingsController(),
          shortcutController: HoldShortcutController(
            dictationController: dictationController,
            registrar: const NoopHoldShortcutRegistrar(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    await dictationController.startListening();
    await tester.pump();
    expect(find.text('Listening'), findsOneWidget);

    final stopFuture = dictationController.stopListening();
    await tester.pump();
    expect(find.text('Transcribing'), findsOneWidget);

    sttEngine.complete('Finished transcript.');
    await stopFuture;
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Listening'), findsNothing);
    expect(find.text('Transcribing'), findsNothing);
  });

  testWidgets(
    'shortcut recorder keeps recording after Ctrl and saves Ctrl+Shift on stop',
    (tester) async {
      await tester.pumpHome(includeShortcutController: true);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Record shortcut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record shortcut'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(find.text('Stop recording'), findsOneWidget);
      expect(find.textContaining('Recording Ctrl'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.textContaining('Recording Ctrl+Shift'), findsOneWidget);

      await tester.tap(find.text('Stop recording'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(find.text('Ctrl+Shift'), findsOneWidget);
      expect(find.text('Record shortcut'), findsOneWidget);
    },
  );

  testWidgets('shortcut recorder auto-saves after three unique keys', (
    tester,
  ) async {
    await tester.pumpHome(includeShortcutController: true);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Record shortcut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record shortcut'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(find.text('Ctrl+Shift+A'), findsOneWidget);
    expect(find.text('Record shortcut'), findsOneWidget);
    expect(find.text('Stop recording'), findsNothing);
  });

  testWidgets('copy button copies a history transcription', (tester) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript('Copy this transcription.');
    await tester.pump();

    await tester.tap(find.byTooltip('Copy transcription'));
    await tester.pump();

    final clipboardCalls = platformCalls
        .where((call) => call.method == 'Clipboard.setData')
        .toList();
    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.arguments, {
      'text': 'Copy this transcription.',
    });
    expect(find.text('Transcription copied'), findsOneWidget);
  });
}

extension on WidgetTester {
  Future<void> pumpHome({
    SttEngine? sttEngine,
    MicrophoneDiscovery? microphoneDiscovery,
    DictationHistoryController? historyController,
    SpeechSettingsController? speechSettingsController,
    bool includeShortcutController = false,
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
    final shortcutController = includeShortcutController
        ? HoldShortcutController(
            dictationController: dictationController,
            registrar: const NoopHoldShortcutRegistrar(),
          )
        : null;

    await pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          historyController: historyController ?? DictationHistoryController(),
          microphoneController: microphoneController,
          speechSettingsController:
              speechSettingsController ?? SpeechSettingsController(),
          shortcutController: shortcutController,
        ),
      ),
    );
    await pump(const Duration(milliseconds: 250));
    await pump(const Duration(milliseconds: 250));
  }
}

class ImmediateAudioRecorder implements AudioRecorder {
  @override
  Future<void> start() async {}

  @override
  Future<AudioRecording> stop() async {
    return const AudioRecording(
      path: 'immediate.wav',
      duration: Duration(milliseconds: 500),
    );
  }
}

class HoldingSttEngine implements SttEngine {
  final Completer<String> _transcriptCompleter = Completer<String>();

  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) {
    return _transcriptCompleter.future;
  }

  void complete(String transcript) {
    _transcriptCompleter.complete(transcript);
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
