import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';

import '../support/fakes.dart';

/// Hangs (times out) until [hangs] is cleared, then transcribes — the
/// shape of a wedged native decoder that later recovers.
class SwitchableHangingSttEngine implements SttEngine {
  SwitchableHangingSttEngine({required this.transcript});

  final String transcript;
  bool hangs = true;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) async {
    if (hangs) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      throw TimeoutException('decoder wedged');
    }
    return transcript;
  }
}

/// The "stuck transcribing forever" bug, end to end: a speech engine that
/// accepts the audio and never answers must NOT strand the app in the
/// transcribing overlay. The app has to surface the failure (error overlay,
/// no inserted text) and accept the very next dictation, which succeeds
/// once the engine answers again — through the production controller,
/// state machine, timeout policy, and UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a hung speech engine surfaces an error and the next dictation recovers',
    (tester) async {
      // Whether the engine answers is the test's dial; hung requests
      // stay pending forever, exactly like a wedged native decoder.
      final sttEngine = SwitchableHangingSttEngine(
        transcript: 'recovered after the outage',
      );

      final dataDirectory = Directory.systemTemp.createTempSync(
        'typemate-e2e-',
      );
      addTearDown(() => dataDirectory.deleteSync(recursive: true));

      final bridge = MockPlatformBridge();
      final registrar = TestHoldShortcutRegistrar();
      final recorderFactory = WavWritingAudioRecorderFactory(
        outputDirectory: dataDirectory,
      );

      await tester.pumpWidget(
        TypeMateApp(
          microphoneDiscovery: FakeMicrophoneDiscovery(),
          holdShortcutRegistrar: registrar,
          sttEngine: sttEngine,
          platformBridge: bridge,
          audioRecorderFactory: recorderFactory,
          dataDirectory: dataDirectory,
          // Desktop hold-shortcut flow; force the desktop shell so it runs
          // identically on the Android emulator.
          useMobileShell: false,
        ),
      );
      await tester.pumpAndSettle();

      // Dictation #1 against the hung server: the overlay must not stay up
      // forever; the failure surfaces as the error overlay and no text.
      await registrar.pressShortcut();
      await tester.pumpAndSettle();
      expect(bridge.overlayVisible, isTrue);

      await registrar.releaseShortcut();
      await tester.pumpAndSettle();

      expect(bridge.overlayVisible, isFalse);
      expect(bridge.lastInsertedText, isEmpty);
      // The failure reason is visible in-app: the failed history entry
      // (every platform) and, on mobile, the mic tile's status line too.
      expect(find.textContaining('Transcription took too long'), findsWidgets);
      // ...and the failure toast (shown at the overlay position, visible
      // outside the app) carries the same reason.
      expect(
        bridge.lastFailureOverlayMessage,
        DictationController.transcriptionTimeoutMessage,
      );
      // The failed dictation kept its recording and offers a retry.
      final retryButton = find.byKey(const Key('history-retry-button'));
      expect(retryButton, findsOneWidget);

      // Engine healthy again: Retry resolves the failed entry in place.
      sttEngine.hangs = false;
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('recovered after the outage'), findsWidgets);
      expect(retryButton, findsNothing);
      expect(find.textContaining('Transcription took too long'), findsNothing);

      // And the normal hotkey loop still works after all of that.
      // Before the fix the app ignored this press forever (still "busy").
      await registrar.pressShortcut();
      await tester.pumpAndSettle();
      expect(bridge.overlayVisible, isTrue);

      await registrar.releaseShortcut();
      await tester.pumpAndSettle();

      expect(bridge.lastInsertedText, 'recovered after the outage');
      expect(bridge.transcribingOverlayCount, 2);
      expect(bridge.overlayVisible, isFalse);

      final historyFile = File('${dataDirectory.path}/history.json');
      expect(historyFile.existsSync(), isTrue);
      expect(
        historyFile.readAsStringSync(),
        contains('recovered after the outage'),
      );
    },
  );

  testWidgets(
    'a failing history store never blocks insertion or the next dictation',
    (tester) async {
      final dataDirectory = Directory.systemTemp.createTempSync(
        'typemate-e2e-',
      );
      addTearDown(() => dataDirectory.deleteSync(recursive: true));
      // A directory squatting on the history file path makes every history
      // write fail — the same shape as a locked or read-only history.json.
      Directory('${dataDirectory.path}/history.json').createSync();

      final bridge = MockPlatformBridge();
      final registrar = TestHoldShortcutRegistrar();
      final recorderFactory = FakeAudioRecorderFactory();
      final sttEngine = FakeSttEngine(transcript: 'typed despite history');

      await tester.pumpWidget(
        TypeMateApp(
          microphoneDiscovery: FakeMicrophoneDiscovery(),
          holdShortcutRegistrar: registrar,
          sttEngine: sttEngine,
          platformBridge: bridge,
          audioRecorderFactory: recorderFactory,
          dataDirectory: dataDirectory,
          useMobileShell: false,
        ),
      );
      await tester.pumpAndSettle();

      for (var round = 0; round < 2; round += 1) {
        await registrar.pressShortcut();
        await tester.pumpAndSettle();
        await registrar.releaseShortcut();
        await tester.pumpAndSettle();
      }

      // Both dictations typed their text; the broken history store neither
      // stranded the overlay nor blocked the second press.
      expect(sttEngine.transcribeCalls, 2);
      expect(bridge.lastInsertedText, 'typed despite history');
      expect(bridge.overlayVisible, isFalse);
      expect(bridge.lastFailureOverlayMessage, isEmpty);
    },
  );
}
