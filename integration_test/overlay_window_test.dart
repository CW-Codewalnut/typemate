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
  // role is detected with a same-process marker file: the main (test)
  // engine writes it before creating the overlay window, and the
  // second engine, entering later in the same process, finds it.
  // Production main.dart branches on entrypoint args instead.
  WidgetsFlutterBinding.ensureInitialized();
  final roleMarker = File(
    '${Directory.systemTemp.path}/typemate-overlay-e2e-$pid.marker',
  );
  if (!Platform.isAndroid &&
      !Platform.resolvedExecutable.contains('flutter_tester')) {
    if (roleMarker.existsSync()) {
      runApp(const OverlayWindowApp());
      return;
    }
    roleMarker.createSync();
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() {
    if (roleMarker.existsSync()) {
      roleMarker.deleteSync();
    }
  });

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

    // The dictation invariant: the overlay never moves input focus
    // away from ANOTHER app. On a CI desktop the test app's own window
    // is foreground, and Windows may shuffle foreground between a
    // process's own windows on z-order changes - harmless, since real
    // dictation targets other apps (live-verified against VS Code on
    // Windows and FeatherPad in the Lubuntu VM). So: focus is either
    // unchanged or still within this process.
    final before = driver!.focusEvidence();
    void expectNoFocusTheft() {
      final after = driver.focusEvidence();
      // In-process shuffling between NON-overlay windows is tolerated
      // (CI desktops foreground the test app itself), but the overlay
      // window taking foreground is exactly the theft this guards.
      expect(
        after == before ||
            (driver.foregroundIsSelf && !driver.overlayStoleFocus),
        isTrue,
        reason:
            'overlay must not move focus away from another app '
            '(before=$before after=$after)',
      );
    }

    await overlay.showWorking('TypeMate is listening...');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expectNoFocusTheft();

    await overlay.showWorking('Transcribing locally...');
    await overlay.showInfo('Please download the speech model first.');
    await overlay.showError("Couldn't capture your voice.");
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expectNoFocusTheft();

    if (Platform.isWindows) {
      // Style readback: NOACTIVATE | LAYERED | TOOLWINDOW | TOPMOST.
      expect(driver.styleEvidence(), contains('exstyle=0x8080088'));
    }

    await overlay.hide();
    // A second cycle must reuse the window without re-creating it.
    await overlay.showWorking('TypeMate is listening...');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expectNoFocusTheft();
    await overlay.hide();
  });
}
