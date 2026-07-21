import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/components/window_title_bar.dart';

void main() {
  Future<void> pumpTitleBar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            WindowTitleBar(showsCaptionButtons: true),
            Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }

  testWidgets('shows the app title and window controls', (tester) async {
    await pumpTitleBar(tester);

    expect(find.text('Type Mate'), findsOneWidget);
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('window control taps survive without a window plugin', (
    tester,
  ) async {
    await pumpTitleBar(tester);

    // In tests there is no native window backing the plugin channel; the
    // buttons must swallow that instead of throwing.
    await tester.tap(find.byTooltip('Minimize'));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
