import 'package:dictation_flow/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the desktop dictation shell', (tester) async {
    await tester.pumpWidget(const DictationFlowApp());

    expect(find.text('TypeMate'), findsOneWidget);
    expect(
      find.text('Local hold to dictate for developers and heavy typers.'),
      findsOneWidget,
    );
    expect(find.text('Prepare local engine'), findsOneWidget);
  });
}
