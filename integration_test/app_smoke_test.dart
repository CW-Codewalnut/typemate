import 'package:typemate/src/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app shell loads with TypeMate title and prepare action', (
    tester,
  ) async {
    await tester.pumpWidget(const DictationFlowApp());
    await tester.pumpAndSettle();

    expect(find.text('TypeMate'), findsOneWidget);
    expect(find.text('Prepare local engine'), findsOneWidget);
    expect(find.text('Hold shortcut preview'), findsOneWidget);
  });
}
