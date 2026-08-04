// The Flutter-rendered dictation overlay: a second Flutter window
// (desktop_multi_window) restyled from the main engine by a
// per-platform [OverlayWindowDriver] - pure Dart FFI, no compiled
// native code. Replaces the retired Win32, X11, and Swift native
// overlay renderers (the macOS driver is build-verified only until a
// real-hardware pass).
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../../../components/overlay_pill.dart';
import 'overlay_variant.dart';
import 'overlay_window_driver.dart';

/// Creates the overlay's window; injectable so tests avoid the real
/// plugin channel.
typedef OverlayWindowCreator =
    Future<OverlayWindowHandle> Function({required bool hiddenAtLaunch});

/// The slice of [WindowController] the overlay needs; tests fake it.
abstract interface class OverlayWindowHandle {
  Future<void> invokeMethod(String method, [dynamic arguments]);
}

class _ChannelHandle implements OverlayWindowHandle {
  _ChannelHandle(this._controller);

  // Held so the window's lifetime is tied to this handle even though
  // calls flow over the fixed-name channel.
  // ignore: unused_field
  final WindowController _controller;

  static const _channel = WindowMethodChannel(
    overlayWindowChannelName,
    mode: ChannelMode.unidirectional,
  );

  @override
  Future<void> invokeMethod(String method, [dynamic arguments]) =>
      _channel.invokeMethod(method, arguments);
}

Future<OverlayWindowHandle> _createRealWindow({
  required bool hiddenAtLaunch,
}) async {
  final controller = await WindowController.create(
    WindowConfiguration(
      arguments: json.encode({'variant': 'working', 'message': ''}),
      hiddenAtLaunch: hiddenAtLaunch,
    ),
  );
  return _ChannelHandle(controller);
}

/// One overlay window per app: created lazily on the first show (one
/// ~600ms warm-up while the sub-engine first-frames), then reused for
/// every show/hide for the rest of the process.
class OverlayWindow {
  OverlayWindow({
    OverlayWindowDriver? driver,
    OverlayWindowCreator? createWindow,
  }) : _createWindow = createWindow ?? _createRealWindow,
       // ignore: prefer_initializing_formals
       _driver = driver;

  /// The production overlay: the running platform's driver, or an
  /// unavailable overlay where none exists.
  factory OverlayWindow.forPlatform() =>
      OverlayWindow(driver: createOverlayWindowDriver());

  final OverlayWindowDriver? _driver;
  final OverlayWindowCreator _createWindow;

  OverlayWindowHandle? _handle;
  Future<void>? _creating;

  /// Whether this platform has a working driver; false falls back to
  /// no overlay at all (the in-app status still shows every state).
  bool get isAvailable => _driver != null;

  /// The animated bars pill with the caller's label.
  Future<void> showWorking(String label) =>
      _show(OverlayVariant.working, label);

  /// Guidance on the primary pill (model download, engine preparing).
  Future<void> showInfo(String message) => _show(OverlayVariant.info, message);

  /// A real failure, on the red pill.
  Future<void> showError(String message) =>
      _show(OverlayVariant.error, message);

  Future<void> hide() async {
    _driver?.hide();
  }

  Future<void> _show(OverlayVariant variant, String message) async {
    final driver = _driver;
    if (driver == null) {
      return;
    }
    await _ensureWindow(driver);
    try {
      await _handle?.invokeMethod(
        'setState',
        json.encode({'variant': variant.name, 'message': message}),
      );
    } catch (error) {
      // The overlay engine may not be listening yet (or at all, in test
      // harnesses that cannot run its entrypoint). The pill then keeps
      // its previous content; dictation itself must never be affected.
      debugPrint('TypeMate: overlay state update failed: $error');
    }
    final isTextPill = variant != OverlayVariant.working;
    driver.show(width: isTextPill ? 360 : 210, height: isTextPill ? 92 : 58);
  }

  Future<void> _ensureWindow(OverlayWindowDriver driver) {
    return _creating ??= () async {
      driver.snapshotBefore();
      _handle = await _createWindow(
        hiddenAtLaunch: !driver.needsVisibleAtLaunch,
      );
      // Give the sub-engine a beat to first-frame before restyling.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!driver.adoptNewWindow()) {
        debugPrint('TypeMate: overlay window adoption failed');
      }
    }();
  }
}
