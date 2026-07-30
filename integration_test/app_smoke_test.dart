import 'dart:io';

import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app shell loads with history and settings', (tester) async {
    final dataDirectory = Directory.systemTemp.createTempSync('typemate-e2e-');
    addTearDown(() => dataDirectory.deleteSync(recursive: true));

    await tester.pumpWidget(
      TypeMateApp(
        sttEngine: MockSttEngine(),
        // The real bridge mutates host state at boot (autostart entries);
        // CI must observe the machine it runs on, not reconfigure it.
        platformBridge: MockPlatformBridge(),
        dataDirectory: dataDirectory,
      ),
    );
    await tester.pumpAndSettle();

    // Mobile's first tab is Dictate (the same page with the mic card);
    // desktop titles it Speech history.
    expect(
      find.text(Platform.isAndroid ? 'Dictate' : 'Speech history'),
      findsWidgets,
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Prepare local engine'), findsNothing);
  });
}
