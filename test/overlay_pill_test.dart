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

  /// The pill's effective colour on any platform: Linux paints it on
  /// the root Material (the X11 shape supplies the corners), the others
  /// on a rounded Container inside the chroma backdrop.
  Color pillColor(WidgetTester tester) {
    for (final container in tester.widgetList<Container>(
      find.byType(Container),
    )) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        return decoration.color!;
      }
    }
    return tester.widgetList<Material>(find.byType(Material)).first.color!;
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
    expect(pillColor(tester), const OverlayTheme.native().pillBackground);
  });

  testWidgets('only the error variant renders the red pill', (tester) async {
    await pump(
      tester,
      variant: OverlayVariant.error,
      message: "Couldn't capture your voice.",
    );

    expect(find.text("Couldn't capture your voice."), findsOneWidget);
    expect(pillColor(tester), const OverlayTheme.native().errorBackground);
  });
}
