import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/components/overlay_pill.dart';
import 'package:typemate/src/core/platform/overlay/overlay_variant.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required OverlayVariant variant,
    required String message,
    bool? paintsEdgeToEdge,
  }) {
    return tester.pumpWidget(
      OverlayWindowApp(
        initialVariant: variant,
        initialMessage: message,
        connectChannel: false,
        paintsEdgeToEdge: paintsEdgeToEdge,
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

  testWidgets('the capsule hugs its message instead of the window', (
    tester,
  ) async {
    // The overlay window is 360x92 for text pills; a one-line message
    // must not inflate the capsule to fill it (a Center inside the pill
    // used to do exactly that, padding the text on all four sides).
    tester.view.physicalSize = const Size(360, 92);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      variant: OverlayVariant.info,
      message: 'Please download the speech model first.',
      // The capsule layout, whatever host the suite runs on.
      paintsEdgeToEdge: false,
    );

    final pill = tester.getSize(
      find.ancestor(
        of: find.text('Please download the speech model first.'),
        matching: find.byType(Container),
      ),
    );
    final text = tester.getSize(
      find.text('Please download the speech model first.'),
    );
    // 10px vertical / 18px horizontal padding, and nothing more.
    expect(pill.height, text.height + 20);
    expect(pill.width, text.width + 36);
    expect(pill.height, lessThan(92));
  });

  testWidgets('the edge-to-edge pill fills the window and centres its text', (
    tester,
  ) async {
    // Linux draws no capsule: the X11 shape cuts the window itself to the
    // pill outline, so the Material paints to every edge and the message
    // centres inside it. Exercised here explicitly because a host-only
    // branch is otherwise unreachable until CI runs it.
    tester.view.physicalSize = const Size(360, 92);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      variant: OverlayVariant.info,
      message: 'Please download the speech model first.',
      paintsEdgeToEdge: true,
    );

    expect(
      find.descendant(
        of: find.byType(Material),
        matching: find.byType(Container),
      ),
      findsNothing,
      reason: 'a capsule would show as a border once X11 shapes the window',
    );
    expect(tester.getSize(find.byType(Material)), const Size(360, 92));
    final textCentre = tester.getCenter(
      find.text('Please download the speech model first.'),
    );
    expect(textCentre.dy, closeTo(46, 0.01));
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
