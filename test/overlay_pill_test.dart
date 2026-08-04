import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/components/overlay_pill.dart';
import 'package:typemate/src/core/platform/overlay/overlay_variant.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required OverlayVariant variant,
    required String message,
  }) {
    return tester.pumpWidget(
      OverlayWindowApp(
        initialVariant: variant,
        initialMessage: message,
        connectChannel: false,
      ),
    );
  }

  Color pillColor(WidgetTester tester) {
    final material = tester.widgetList<Material>(find.byType(Material)).first;
    if (material.color != null) {
      return material.color!;
    }
    final container = tester
        .widgetList<Container>(find.byType(Container))
        .first;
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('working variant shows the caller label with bars', (
    tester,
  ) async {
    await pump(
      tester,
      variant: OverlayVariant.working,
      message: 'TypeMate is listening...',
    );

    expect(find.text('TypeMate is listening...'), findsOneWidget);

    // Fresh tree: the message is initial state, not a prop update.
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(
      tester,
      variant: OverlayVariant.working,
      message: 'Transcribing locally...',
    );
    expect(find.text('Transcribing locally...'), findsOneWidget);
    // Cap the bars animation timer before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('info guidance renders on the primary pill, not red', (
    tester,
  ) async {
    await pump(
      tester,
      variant: OverlayVariant.info,
      message: 'Please download the speech model first.',
    );

    expect(
      find.text('Please download the speech model first.'),
      findsOneWidget,
    );
    final theme = const OverlayTheme.native();
    expect(pillColor(tester), isNot(theme.errorBackground));
  });

  testWidgets('only the error variant renders the red pill', (tester) async {
    await pump(
      tester,
      variant: OverlayVariant.error,
      message: "Couldn't capture your voice.",
    );

    expect(find.text("Couldn't capture your voice."), findsOneWidget);
    final container = tester
        .widgetList<Container>(find.byType(Container))
        .first;
    expect(
      (container.decoration! as BoxDecoration).color,
      const OverlayTheme.native().errorBackground,
    );
  });
}
