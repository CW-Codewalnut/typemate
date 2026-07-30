import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/parakeet_server_stt_engine.dart';

import 'support/fakes.dart';

/// The "stuck transcribing forever" bug, end to end: a local speech server
/// that accepts the audio and never answers must NOT strand the app in the
/// transcribing overlay. The app has to surface the failure (error overlay,
/// no inserted text) and accept the very next dictation, which succeeds once
/// the server answers again — all through the production engine, controller,
/// state machine, and UI, over a real loopback websocket.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a hung speech server surfaces an error and the next dictation recovers',
    (tester) async {
      // Real websocket server; whether it answers is the test's dial.
      var serverAnswers = false;
      final speechServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => speechServer.close(force: true));
      speechServer.listen((request) async {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          if (serverAnswers) {
            socket.add('{"text": "recovered after the outage"}');
          }
          // else: swallow the audio and never reply — the hang under test.
        });
      });

      final dataDirectory = Directory.systemTemp.createTempSync(
        'typemate-e2e-',
      );
      addTearDown(() => dataDirectory.deleteSync(recursive: true));

      final bridge = MockPlatformBridge();
      final registrar = TestHoldShortcutRegistrar();
      final recorderFactory = WavWritingAudioRecorderFactory(
        outputDirectory: dataDirectory,
      );
      // The production English engine, adopting the test server on its port.
      // Short timeouts keep the test fast; the production defaults differ
      // only in duration.
      final sttEngine = ParakeetServerSttEngine(
        serverExecutable: 'unused: the server is already reachable',
        encoderPath: 'unused',
        decoderPath: 'unused',
        joinerPath: 'unused',
        tokensPath: 'unused',
        port: speechServer.port,
        responseTimeout: const Duration(seconds: 2),
        socketCloseTimeout: const Duration(seconds: 1),
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
      // ...and the OS notification (read outside the app, persists in the
      // tray) is the one place that points back at History.
      expect(
        bridge.lastFailureNotification,
        '${DictationController.transcriptionTimeoutMessage}'
        '${DictationController.retryFromHistoryHint}',
      );
      // The failed dictation kept its recording and offers a retry.
      final retryButton = find.byKey(const Key('history-retry-button'));
      expect(retryButton, findsOneWidget);

      // Server healthy again: Retry resolves the failed entry in place.
      serverAnswers = true;
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
      expect(bridge.lastFailureNotification, isEmpty);
    },
  );
}
