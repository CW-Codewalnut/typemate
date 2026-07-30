import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';

import 'support/fakes.dart';

/// The product loop, end to end, on the real desktop embedder of whichever
/// OS this runs on: hold the shortcut, speak, release, and the transcript
/// is inserted into the focused field and logged to history. Native
/// adapters (global key hook, microphone, text injection) are faked so the
/// run is deterministic on headless CI runners; everything between them —
/// controllers, state machine, persistence, UI — is the production code.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hold-to-talk dictation loop inserts and logs the transcript', (
    tester,
  ) async {
    const transcript = 'end to end dictation works';
    final dataDirectory = Directory.systemTemp.createTempSync('typemate-e2e-');
    addTearDown(() => dataDirectory.deleteSync(recursive: true));

    final bridge = MockPlatformBridge();
    final registrar = TestHoldShortcutRegistrar();
    final recorderFactory = FakeAudioRecorderFactory();
    final sttEngine = FakeSttEngine(transcript: transcript);

    await tester.pumpWidget(
      TypeMateApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: registrar,
        sttEngine: sttEngine,
        platformBridge: bridge,
        audioRecorderFactory: recorderFactory,
        dataDirectory: dataDirectory,
        // This exercises the desktop hold-shortcut loop; force the desktop
        // shell so it runs the same way on the Android emulator (where the
        // mobile shell would null the shortcut and lazy-load the engine).
        useMobileShell: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(registrar.isRegistered, isTrue);
    // The desktop shell prepares the engine during init; wait for it
    // rather than racing the first frame.
    await pumpUntil(tester, () => sttEngine.prepared);
    expect(sttEngine.prepared, isTrue);

    // Hold the shortcut: the overlay shows and recording starts.
    await registrar.pressShortcut();
    await tester.pumpAndSettle();

    expect(bridge.overlayVisible, isTrue);
    expect(recorderFactory.createdRecorders, hasLength(1));
    expect(recorderFactory.createdRecorders.single.isRecording, isTrue);

    // Release: transcribe, insert into the focused field, log to history.
    await registrar.releaseShortcut();
    await tester.pumpAndSettle();

    expect(sttEngine.transcribeCalls, 1);
    expect(recorderFactory.createdRecorders.single.isRecording, isFalse);
    expect(bridge.lastInsertedText, transcript);
    expect(bridge.transcribingOverlayCount, 1);
    expect(bridge.overlayVisible, isFalse);

    // The transcript is visible on the history page.
    expect(find.textContaining(transcript), findsWidgets);

    // And persisted, so it survives an app restart.
    final historyFile = File('${dataDirectory.path}/history.json');
    expect(historyFile.existsSync(), isTrue);
    expect(historyFile.readAsStringSync(), contains(transcript));
  });

  testWidgets('a second dictation appends without leaking recorder state', (
    tester,
  ) async {
    final dataDirectory = Directory.systemTemp.createTempSync('typemate-e2e-');
    addTearDown(() => dataDirectory.deleteSync(recursive: true));

    final bridge = MockPlatformBridge();
    final registrar = TestHoldShortcutRegistrar();
    final recorderFactory = FakeAudioRecorderFactory();
    final sttEngine = FakeSttEngine(transcript: 'again and again');

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

    expect(sttEngine.transcribeCalls, 2);
    expect(recorderFactory.createdRecorders, hasLength(2));
    expect(bridge.lastInsertedText, 'again and again');

    final historyFile = File('${dataDirectory.path}/history.json');
    final decoded =
        jsonDecode(historyFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['entries'], hasLength(2));
  });
}
