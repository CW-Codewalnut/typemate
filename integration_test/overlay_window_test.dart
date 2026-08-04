import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/components/overlay_pill.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window_driver.dart';

/// The real overlay stack, end to end: a second Flutter engine renders
/// the pill and the platform driver restyles it over FFI - shown,
/// restyled, cycled through every variant, and hidden, while the
/// decisive dictation invariant holds: the overlay window never takes
/// input focus (a stolen focus would send the transcript to the wrong
/// window).
///
/// Desktop-only: Android renders its overlay through the accessibility
/// service, and flutter-tester registers no native plugins.
Future<void> main() async {
  // The overlay's second engine re-enters THIS main (the test binary is
  // the app), but the test harness only supports a no-arg main - so the
  // role is detected at runtime: the multi-window class window only
  // exists once the main engine created it, i.e. in the overlay engine.
  // Production main.dart branches on entrypoint args instead.
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid &&
      !Platform.resolvedExecutable.contains('flutter_tester')) {
    final roleProbe = createOverlayWindowDriver();
    if (roleProbe != null && roleProbe.isSecondaryEngine) {
      runApp(const OverlayWindowApp());
      return;
    }
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('overlay window shows every variant without taking focus', (
    tester,
  ) async {
    if (Platform.isAndroid) {
      markTestSkipped('the Android overlay is the accessibility service');
      return;
    }
    if (Platform.resolvedExecutable.contains('flutter_tester')) {
      markTestSkipped('no native plugins on flutter-tester');
      return;
    }

    final OverlayWindowDriver? driver = createOverlayWindowDriver();
    expect(driver, isNotNull, reason: 'desktop platforms must have a driver');
    final overlay = OverlayWindow(driver: driver);
    expect(overlay.isAvailable, isTrue);

    await overlay.showWorking('TypeMate is listening...');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(driver!.overlayStoleFocus, isFalse);

    await overlay.showWorking('Transcribing locally...');
    await overlay.showInfo('Please download the speech model first.');
    await overlay.showError("Couldn't capture your voice.");
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(driver.overlayStoleFocus, isFalse);

    if (Platform.isWindows) {
      // Style readback: NOACTIVATE | LAYERED | TOOLWINDOW | TOPMOST.
      expect(driver.styleEvidence(), contains('exstyle=0x8080088'));
    }

    await overlay.hide();
    // A second cycle must reuse the window without re-creating it.
    await overlay.showWorking('TypeMate is listening...');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(driver.overlayStoleFocus, isFalse);
    await overlay.hide();
  });
}
