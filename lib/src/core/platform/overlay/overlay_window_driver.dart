// The per-platform contract for styling and showing the overlay window
// that desktop_multi_window created. Every implementation works from
// the MAIN engine with pure Dart FFI - no compiled native code.
import 'dart:io';

import '../macos/macos_overlay_window_driver.dart';
import '../windows/windows_overlay_window_driver.dart';
import '../linux/linux_x11_overlay_window_driver.dart';

abstract class OverlayWindowDriver {
  /// Records the process's window set so [adoptNewWindow] can identify
  /// the one desktop_multi_window creates next. No-op where the window
  /// is found another way.
  void snapshotBefore() {}

  /// Whether the overlay window must launch visible for the platform to
  /// realize a native window that can be adopted (Linux/GTK).
  bool get needsVisibleAtLaunch => false;

  /// Claims the newly created window and applies the one-time styling
  /// that makes it an overlay (frameless, topmost, non-activating).
  bool adoptNewWindow() => true;

  /// Sizes/positions the overlay (logical pixels, bottom-centre) and
  /// shows it WITHOUT stealing focus.
  bool show({required int width, required int height});

  void hide();

  /// Human-readable focus evidence for the spike logs.
  String focusEvidence();

  /// The decisive check: whether the overlay window itself now holds
  /// input focus (must always be false).
  bool get overlayStoleFocus;

  /// Extra styling evidence for the logs (e.g. Win32 exstyle readback).
  String styleEvidence() => '';

  /// Whether this engine is the overlay's secondary engine (a window of
  /// the multi-window class already exists in this process). The test
  /// harness cannot branch on entrypoint args, so its main() asks this
  /// instead; production main.dart branches on args and never needs it.
  bool get isSecondaryEngine => false;
}

/// Returns the platform's driver, or null where none exists yet.
OverlayWindowDriver? createOverlayWindowDriver() {
  if (Platform.isWindows) {
    return WindowsOverlayWindowDriver();
  }
  if (Platform.isLinux) {
    return X11OverlayWindowDriver();
  }
  if (Platform.isMacOS) {
    return MacosOverlayWindowDriver();
  }
  return null;
}
