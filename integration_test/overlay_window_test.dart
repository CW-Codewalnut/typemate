import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/components/overlay_pill.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window_driver.dart';

/// Forces this process's main window to the foreground (Windows only),
/// reproducing the CI desktop - where the test app itself holds focus -
/// deterministically on developer machines too. The ALT-tap unlocks
/// SetForegroundWindow's foreground-lock rules.
void _forceOwnWindowForeground() {
  if (!Platform.isWindows) {
    return;
  }
  final user32 = DynamicLibrary.open('user32.dll');
  final findWindow = user32
      .lookupFunction<
        IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)
      >('FindWindowW');
  final setForeground = user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetForegroundWindow',
      );
  final keybdEvent = user32
      .lookupFunction<
        Void Function(Uint8, Uint8, Uint32, IntPtr),
        void Function(int, int, int, int)
      >('keybd_event');
  final title = 'Type Mate'.toNativeUtf16();
  try {
    final hwnd = findWindow(nullptr, title);
    if (hwnd == 0) {
      return;
    }
    const vkMenu = 0x12;
    const keyUp = 0x2;
    keybdEvent(vkMenu, 0, 0, 0);
    setForeground(hwnd);
    keybdEvent(vkMenu, 0, keyUp, 0);
  } finally {
    malloc.free(title);
  }
}

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

    // Production shape: the window is preloaded at app boot, so its
    // one-time creation (whose child-view focus grab is the package's
    // behavior, not a show-path leak) happens before any dictation.
    overlay.preload();
    await Future<void>.delayed(const Duration(seconds: 2));

    // Reproduce the CI desktop deterministically: the test app's own
    // window holds foreground when the overlay shows.
    _forceOwnWindowForeground();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The dictation invariant: showing/hiding the overlay never moves
    // input focus away from whoever holds it. In-process shuffling
    // between NON-overlay windows is tolerated, but the overlay window
    // taking foreground is exactly the theft this guards.
    final before = driver!.focusEvidence();
    // Printed so CI logs show which desktop condition actually ran
    // (own-window foreground = the strict case).
    debugPrint('OVERLAY-E2E|before=$before');
    void expectNoFocusTheft() {
      final after = driver.focusEvidence();
      expect(
        after == before ||
            (driver.foregroundIsSelf && !driver.overlayStoleFocus),
        isTrue,
        reason:
            'overlay must not move focus away from another app '
            '(before=$before after=$after '
            'foregroundIsSelf=${driver.foregroundIsSelf} '
            'overlayStoleFocus=${driver.overlayStoleFocus} '
            '${driver.styleEvidence()})',
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
