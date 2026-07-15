import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app shell loads with history and settings', (tester) async {
    await tester.pumpWidget(DictationFlowApp(sttEngine: MockSttEngine()));
    await tester.pumpAndSettle();

    expect(find.text('TypeMate'), findsOneWidget);
    expect(find.text('Speech history'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Prepare local engine'), findsNothing);
  });
}
