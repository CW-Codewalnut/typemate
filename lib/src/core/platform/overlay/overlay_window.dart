// The Flutter-rendered dictation overlay: a second Flutter window
// (desktop_multi_window) restyled from the main engine by a
// per-platform [OverlayWindowDriver] - pure Dart FFI, no compiled
// native code. Replaces the retired Win32, X11, and Swift native
// overlay renderers (the macOS driver is build-verified only until a
// real-hardware pass).
import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../components/overlay_pill.dart';
import 'overlay_variant.dart';
import 'overlay_window_driver.dart';

/// Creates the overlay's window; injectable so tests avoid the real
/// plugin channel.
typedef OverlayWindowCreator =
    Future<OverlayWindowHandle> Function({
      required bool hiddenAtLaunch,
      required String arguments,
    });

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
  required String arguments,
}) async {
  final controller = await WindowController.create(
    WindowConfiguration(arguments: arguments, hiddenAtLaunch: hiddenAtLaunch),
  );
  return _ChannelHandle(controller);
}

/// One overlay window per app, ideally created by [preload] during app
/// bootstrap so no dictation ever waits on second-engine bring-up, then
/// reused for every show/hide for the rest of the process.
class OverlayWindow {
  OverlayWindow({
    OverlayWindowDriver? driver,
    OverlayWindowCreator? createWindow,
    this.textPillAutoHideAfter = const Duration(milliseconds: 4500),
  }) : _createWindow = createWindow ?? _createRealWindow,
       // ignore: prefer_initializing_formals
       _driver = driver;

  /// The production overlay: the running platform's driver, or an
  /// unavailable overlay where none exists.
  factory OverlayWindow.forPlatform() =>
      OverlayWindow(driver: createOverlayWindowDriver());

  final OverlayWindowDriver? _driver;
  final OverlayWindowCreator _createWindow;

  /// How long an info/error pill stays up before hiding itself - the
  /// retired native overlays all auto-hid at 4.5s. Working pills never
  /// auto-hide (the dictation lifecycle hides them).
  final Duration textPillAutoHideAfter;

  OverlayWindowHandle? _handle;
  Future<void>? _creating;
  Timer? _autoHide;

  /// Whether this platform has a working driver; false falls back to
  /// no overlay at all (the in-app status still shows every state).
  bool get isAvailable => _driver != null;

  /// Creates the overlay window ahead of time, off the dictation
  /// critical path: without this the first dictation's showListening
  /// would wait on second-engine bring-up while the user is already
  /// speaking. Safe to call any number of times.
  void preload() {
    final driver = _driver;
    if (driver == null) {
      return;
    }
    unawaited(
      _ensureWindow(driver, OverlayVariant.working, '').catchError((
        Object error,
      ) {
        // MissingPluginException is the expected shape in unit-test
        // harnesses (no desktop_multi_window plugin registered) - not
        // worth a log line there; anything else is.
        if (error is! MissingPluginException) {
          debugPrint('TypeMate: overlay preload failed: $error');
        }
      }),
    );
  }

  /// The animated bars pill with the caller's label.
  Future<void> showWorking(String label) =>
      _show(OverlayVariant.working, label);

  /// Guidance on the primary pill (model download, engine preparing).
  Future<void> showInfo(String message) => _show(OverlayVariant.info, message);

  /// A real failure, on the red pill.
  Future<void> showError(String message) =>
      _show(OverlayVariant.error, message);

  Future<void> hide() async {
    _autoHide?.cancel();
    _autoHide = null;
    // Pause the pill (stops its animation) before hiding the native
    // window, so a hidden overlay burns no cycles.
    try {
      await _handle?.invokeMethod('setState', json.encode({'hidden': true}));
    } catch (_) {
      // The overlay engine may not be listening; hiding still proceeds.
    }
    _driver?.hide();
  }

  Future<void> _show(OverlayVariant variant, String message) async {
    final driver = _driver;
    if (driver == null) {
      return;
    }
    _autoHide?.cancel();
    _autoHide = null;
    try {
      await _ensureWindow(driver, variant, message);
    } catch (error) {
      // A broken overlay must never affect dictation: swallow the
      // failure (creation may retry on the next show) and skip the
      // pill for this one.
      debugPrint('TypeMate: overlay window creation failed: $error');
      return;
    }
    try {
      await _handle?.invokeMethod(
        'setState',
        json.encode({
          'variant': variant.name,
          'message': message,
          'hidden': false,
        }),
      );
    } catch (error) {
      // The overlay engine may not be listening yet (or at all, in test
      // harnesses that cannot run its entrypoint). The pill then keeps
      // its creation-time content; dictation itself must never be
      // affected.
      debugPrint('TypeMate: overlay state update failed: $error');
    }
    final isTextPill = variant != OverlayVariant.working;
    driver.show(width: isTextPill ? 360 : 210, height: isTextPill ? 92 : 58);
    if (isTextPill) {
      // Info/error are transient toasts: without this they would sit
      // topmost on screen forever (the native overlays auto-hid too).
      _autoHide = Timer(textPillAutoHideAfter, () {
        _autoHide = null;
        unawaited(hide());
      });
    }
  }

  Future<void> _ensureWindow(
    OverlayWindowDriver driver,
    OverlayVariant variant,
    String message,
  ) {
    return _creating ??= () async {
      try {
        await _createAndAdopt(driver, variant, message);
      } catch (error) {
        // Un-memoize so a transient failure (e.g. the platform channel
        // not ready yet) can retry on a later show instead of poisoning
        // every dictation for the rest of the process.
        _creating = null;
        rethrow;
      }
    }();
  }

  Future<void> _createAndAdopt(
    OverlayWindowDriver driver,
    OverlayVariant variant,
    String message,
  ) async {
    driver.snapshotBefore();
    _handle = await _createWindow(
      hiddenAtLaunch: !driver.needsVisibleAtLaunch,
      // The first pill content rides the creation arguments, so even
      // a show that beats the channel-handler registration renders
      // the right variant and message.
      arguments: json.encode({'variant': variant.name, 'message': message}),
    );
    // Adopt as soon as the native window exists instead of a fixed
    // wait: on Linux the window is briefly WM-managed and visible, so
    // every spared millisecond shrinks that flash (preload moves it
    // to app boot entirely).
    for (var attempt = 0; attempt < 24; attempt++) {
      if (driver.adoptNewWindow()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    debugPrint('TypeMate: overlay window adoption failed');
  }
}
