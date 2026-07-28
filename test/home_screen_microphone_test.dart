import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/components/content_page_shell.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/audio/mock_audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/dictation_history_controller.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
import 'package:typemate/src/features/home/home_screen.dart';

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
        find.text('Press and hold Ctrl+Win and start speaking.'),
        findsOneWidget,
      );
      expect(find.text('Ready. Hold the shortcut and speak.'), findsNothing);
    },
  );

  testWidgets(
    'a failed dictation appears in history with its reason and a retry',
    (tester) async {
      final historyController = DictationHistoryController();
      final dictationController = DictationController(
        platformBridge: MockPlatformBridge(),
        sttEngine: FailingSttEngine(),
        audioRecorder: ImmediateAudioRecorder(),
        onTranscriptionFailed: historyController.addFailure,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            controller: dictationController,
            historyController: historyController,
            microphoneController: MicrophoneSettingsController(
              discovery: FakeMicrophoneDiscovery(const []),
            ),
            speechSettingsController: SpeechSettingsController(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      await dictationController.startListening();
      await dictationController.stopListening();
      await tester.pump();

      expect(find.textContaining('turn your speech into text'), findsWidgets);
      // No kept recording (the fake recorder leaves no file), so the entry
      // shows a disabled retry.
      expect(find.byKey(const Key('history-retry-button')), findsOneWidget);
    },
  );

  testWidgets('shows the engine starting state until prepare completes', (
    tester,
  ) async {
    final engine = HoldingPrepareSttEngine();
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: engine,
      audioRecorder: ImmediateAudioRecorder(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          historyController: DictationHistoryController(),
          microphoneController: MicrophoneSettingsController(
            discovery: FakeMicrophoneDiscovery(const []),
          ),
          speechSettingsController: SpeechSettingsController(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    // The hotkey does nothing while the engine loads; the page says so
    // instead of showing a dictation instruction that will not work.
    expect(find.textContaining('Starting the speech engine'), findsOneWidget);
    expect(find.textContaining('Press and hold'), findsNothing);

    engine.completePrepare();
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Starting the speech engine'), findsNothing);
    expect(find.textContaining('Press and hold'), findsOneWidget);
  });

  testWidgets(
    'a failed entry shows its auto-delete date and deletes on demand',
    (tester) async {
      final historyController = DictationHistoryController();
      final dictationController = DictationController(
        platformBridge: MockPlatformBridge(),
        sttEngine: MockSttEngine(),
        audioRecorder: ImmediateAudioRecorder(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            controller: dictationController,
            historyController: historyController,
            microphoneController: MicrophoneSettingsController(
              discovery: FakeMicrophoneDiscovery(const []),
            ),
            speechSettingsController: SpeechSettingsController(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await historyController.addFailure('failed', recordingPath: 'kept.wav');
      await tester.pump();

      expect(find.textContaining('Auto-deletes in 30 days'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-delete-button')));
      await tester.pump();

      expect(historyController.entries, isEmpty);
      expect(find.byKey(const Key('history-delete-button')), findsNothing);
    },
  );

  testWidgets('a transcript can be deleted individually', (tester) async {
    final historyController = DictationHistoryController();
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorder: ImmediateAudioRecorder(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          historyController: historyController,
          microphoneController: MicrophoneSettingsController(
            discovery: FakeMicrophoneDiscovery(const []),
          ),
          speechSettingsController: SpeechSettingsController(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await historyController.addTranscript('keep this one');
    await historyController.addTranscript('delete this one');
    await tester.pump();

    // Entries are newest-first, so the first delete belongs to the entry
    // added last.
    final deleteButtons = find.byKey(const Key('history-delete-button'));
    expect(deleteButtons, findsNWidgets(2));

    await tester.tap(deleteButtons.first);
    await tester.pump();

    expect(find.text('delete this one'), findsNothing);
    expect(find.text('keep this one'), findsOneWidget);
    expect(historyController.entries.single.text, 'keep this one');
  });

  testWidgets('other retries disable while one retry is transcribing', (
    tester,
  ) async {
    final historyController = DictationHistoryController();
    final holdingEngine = HoldingSttEngine();
    final dictationController = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: holdingEngine,
      audioRecorder: ImmediateAudioRecorder(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: dictationController,
          historyController: historyController,
          microphoneController: MicrophoneSettingsController(
            discovery: FakeMicrophoneDiscovery(const []),
          ),
          speechSettingsController: SpeechSettingsController(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    // After the shell's history load; loading earlier would be wiped.
    await historyController.addFailure('failed one', recordingPath: 'one.wav');
    await historyController.addFailure('failed two', recordingPath: 'two.wav');
    await tester.pump();

    final retryButtons = find.byKey(const Key('history-retry-button'));
    expect(retryButtons, findsNWidgets(2));

    await tester.tap(retryButtons.first);
    await tester.pump();

    // The tapped retry shows progress; every other retry is disabled
    // because only one transcription can run at a time.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final innerButtons = find.descendant(
      of: retryButtons,
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(tester.widget<TextButton>(innerButtons).onPressed, isNull);

    holdingEngine.complete('recovered');
    await tester.pump();
    await tester.pump();

    // The finished retry resolved its entry; the other retry re-enables.
    expect(retryButtons, findsOneWidget);
    expect(tester.widget<TextButton>(innerButtons).onPressed, isNotNull);
  });

  testWidgets('insights page shows real local usage metrics and streak grid', (
    tester,
  ) async {
    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Ship local dictation quickly',
      duration: const Duration(seconds: 30),
    );
    await historyController.addTranscript(
      'Create reports',
      duration: const Duration(seconds: 30),
    );
    await tester.pump();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insights-page')), findsOneWidget);
    expect(find.text('Your Usage'), findsNothing);
    expect(find.text('Your Voice'), findsNothing);
    expect(find.text('Leaderboard'), findsNothing);
    expect(find.text('Words per minute'), findsOneWidget);
    expect(find.text('Dictation sessions'), findsOneWidget);
    expect(find.text('Total words dictated'), findsOneWidget);
    expect(find.text('Dictation activity'), findsOneWidget);
    expect(find.text('6 words from local history'), findsOneWidget);
    expect(find.text('6 TODAY'), findsOneWidget);
    expect(find.text('TOTAL SESSIONS | 2'), findsOneWidget);
    expect(find.text('1 day streak'), findsOneWidget);
    expect(find.text('LONGEST STREAK | 1 DAY'), findsOneWidget);
    expect(find.byKey(const Key('insights-streak-grid')), findsOneWidget);
  });

  testWidgets('streak grid weekday labels render on a single line', (
    tester,
  ) async {
    final historyController = DictationHistoryController();
    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Ship local dictation quickly',
      duration: const Duration(seconds: 30),
    );
    await tester.pump();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    for (final label in const [
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ]) {
      final size = tester.getSize(find.text(label));
      expect(
        size.height,
        lessThan(24),
        reason: '$label should not wrap onto a second line',
      );
    }
  });

  testWidgets('insights card labels scale down instead of truncating', (
    tester,
  ) async {
    final historyController = DictationHistoryController();
    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Ship local dictation quickly',
      duration: const Duration(seconds: 30),
    );
    await tester.pump();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    for (final key in const [
      'insights-total-sessions',
      'insights-current-streak',
      'insights-longest-streak',
    ]) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key)),
          matching: find.byType(FittedBox),
        ),
        findsWidgets,
        reason: '$key should scale down to fit instead of showing an ellipsis',
      );
    }
  });

  testWidgets('history entries stack the time above the transcript on '
      'mobile width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final historyController = DictationHistoryController();
    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Ship local dictation quickly',
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    final timeFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data ?? ''),
    );
    final transcriptFinder = find.text('Ship local dictation quickly');

    expect(timeFinder, findsOneWidget);
    expect(
      tester.getTopLeft(transcriptFinder).dy,
      greaterThan(tester.getBottomLeft(timeFinder).dy - 1),
      reason: 'transcript should sit below the time on narrow layouts',
    );
    expect(
      tester.getTopLeft(transcriptFinder).dx,
      moreOrLessEquals(tester.getTopLeft(timeFinder).dx, epsilon: 1),
      reason: 'transcript should align with the time, not indent past it',
    );
  });

  testWidgets('history entries keep the time beside the transcript on '
      'desktop width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final historyController = DictationHistoryController();
    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Ship local dictation quickly',
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    final timeFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data ?? ''),
    );
    final transcriptFinder = find.text('Ship local dictation quickly');

    expect(
      tester.getTopLeft(transcriptFinder).dx,
      greaterThan(tester.getTopRight(timeFinder).dx),
      reason: 'transcript should sit beside the time on wide layouts',
    );
  });

  testWidgets('settings page uses the shared content shell layout', (
    tester,
  ) async {
    await tester.pumpHome(
      microphoneDiscovery: FakeMicrophoneDiscovery(const []),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(ContentPageShell), findsOneWidget);
  });

  testWidgets('insights page lays out at desktop width without exceptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpHome();
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('insights-page')), findsOneWidget);
  });

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
    expect(find.text('2 microphones found.'), findsNothing);
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
        'Unable to scan microphones. Check the microphone and its permissions, then reopen Settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Refresh microphones'), findsNothing);
  });

  testWidgets('settings page wires language selection to Whisper.cpp', (
    tester,
  ) async {
    final speechSettingsController = SpeechSettingsController();
    await tester.pumpHome(speechSettingsController: speechSettingsController);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Speech recognition'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.textContaining('Model:'), findsNothing);
    expect(find.textContaining('Whisper.cpp'), findsNothing);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hindi').last);
    await tester.pumpAndSettle();

    expect(speechSettingsController.languageCode, 'hi');
  });

  testWidgets('empty history state is centered without a card', (tester) async {
    await tester.pumpHome();
    await tester.pump();

    final emptyState = find.byKey(const Key('empty-history-state'));
    expect(emptyState, findsOneWidget);
    expect(
      find.descendant(of: emptyState, matching: find.byType(Card)),
      findsNothing,
    );
    expect(find.text('No speech history yet.'), findsOneWidget);
  });

  testWidgets('history page shows generated speech text', (tester) async {
    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript('Ship the local dictation flow.');
    await tester.pump();

    expect(find.text('Ship the local dictation flow.'), findsOneWidget);
  });

  testWidgets('history page hides the scrollbar chrome', (tester) async {
    await tester.pumpHome();

    expect(find.byKey(const Key('history-scrollbar-hidden')), findsOneWidget);
  });

  testWidgets('history page keeps content anchored near the top', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpHome();
    await tester.pump();

    final titleTop = tester.getTopLeft(find.text('Speech history')).dy;

    expect(titleTop, lessThan(80));
  });

  testWidgets('history page does not show stats report cards', (tester) async {
    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Keep history focused on transcripts only',
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-main-column')), findsOneWidget);
    expect(find.byKey(const Key('history-stats-rail')), findsNothing);
    expect(find.byKey(const Key('history-mobile-stats-card')), findsNothing);
    expect(find.byKey(const Key('history-report-card')), findsNothing);
    expect(find.text('total words'), findsNothing);
    expect(find.text('wpm'), findsNothing);
  });

  testWidgets('insights mobile layout does not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final historyController = DictationHistoryController();

    await tester.pumpHome(historyController: historyController);
    await historyController.addTranscript(
      'Mobile insights should fit without clipping',
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insights-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses bottom navigation on mobile width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpHome();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('shortcut dictation does not render a duplicate in-app overlay', (
    tester,
  ) async {
    final sttEngine = HoldingSttEngine();
    final platformBridge = MockPlatformBridge();
    final dictationController = DictationController(
      platformBridge: platformBridge,
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
    expect(platformBridge.overlayVisible, isTrue);
    expect(find.text('Listening'), findsNothing);

    final stopFuture = dictationController.stopListening();
    await tester.pump();
    expect(find.text('Transcribing'), findsNothing);

    sttEngine.complete('Finished transcript.');
    await stopFuture;
    await tester.pump(const Duration(milliseconds: 50));
    expect(platformBridge.overlayVisible, isFalse);
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

class HoldingPrepareSttEngine implements SttEngine {
  final Completer<void> _prepared = Completer<void>();

  void completePrepare() => _prepared.complete();

  @override
  Future<bool> isReady() async => _prepared.isCompleted;

  @override
  Future<void> prepare() => _prepared.future;

  @override
  Future<String> transcribe(AudioRecording recording) async => '';
}

class FailingSttEngine implements SttEngine {
  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) async {
    throw StateError('engine down');
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
