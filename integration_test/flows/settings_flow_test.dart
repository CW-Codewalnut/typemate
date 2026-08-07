import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';

import '../support/fakes.dart';

/// Settings, end to end: navigate there, see the discovered microphone
/// selected, switch the speech language, and verify the choice is written
/// to disk so it survives a restart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('language change from Settings persists to disk', (tester) async {
    final dataDirectory = Directory.systemTemp.createTempSync('typemate-e2e-');
    addTearDown(() => dataDirectory.deleteSync(recursive: true));

    final sttEngine = FakeSttEngine(transcript: 'unused');
    await tester.pumpWidget(
      TypeMateApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: TestHoldShortcutRegistrar(),
        sttEngine: sttEngine,
        platformBridge: MockPlatformBridge(),
        audioRecorderFactory: FakeAudioRecorderFactory(),
        dataDirectory: dataDirectory,
      ),
    );
    await tester.pumpAndSettle();

    // Navigate: the shell starts on History; Settings is on the rail.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // The fake microphone was auto-selected as the input device.
    expect(find.text(FakeMicrophoneDiscovery.microphoneName), findsOneWidget);

    // Switch to Bulgarian: a Parakeet language (so it exists in the picker
    // on every platform, unlike the whisper-only ones absent on Android)
    // and near the top of the list, so it renders in the open dropdown.
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulgarian').last);
    await tester.pumpAndSettle();

    // The change is persisted for the next launch and the engine is
    // re-prepared so the newly selected model is warm.
    final settingsFile = File('${dataDirectory.path}/speech-settings.json');
    expect(settingsFile.existsSync(), isTrue);
    final decoded =
        jsonDecode(settingsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['languageCode'], 'bg');
  });
}
