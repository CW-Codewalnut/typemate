// The Flutter-rendered dictation overlay: a second Flutter window
// (desktop_multi_window) restyled from the main engine by a
// per-platform [OverlayWindowDriver] - pure Dart FFI, no compiled
// native code. Replaces the retired Win32, X11, and Swift native
// overlay renderers (the macOS driver is build-verified only until a
// real-hardware pass).
import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/painting.dart';
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

  /// Whether the native window this handle describes still exists.
  ///
  /// Needed because a failed [invokeMethod] does not say WHY: the overlay
  /// engine may simply not have registered its handler yet (a show racing
  /// bring-up), or the window may be gone for good. desktop_multi_window
  /// offers no way to close a window, so rebuilding on a transient error
  /// would strand the old window and its engine with no way to reclaim
  /// them — worse than the missing-overlay bug this recovery exists for.
  Future<bool> isAlive();
}

class _ChannelHandle implements OverlayWindowHandle {
  _ChannelHandle(this._controller);

  // Held both to tie the window's lifetime to this handle (calls flow
  // over the fixed-name channel) and to identify it in getAll().
  final WindowController _controller;

  static const _channel = WindowMethodChannel(
    overlayWindowChannelName,
    mode: ChannelMode.unidirectional,
  );

  @override
  Future<void> invokeMethod(String method, [dynamic arguments]) =>
      _channel.invokeMethod(method, arguments);

  @override
  Future<bool> isAlive() async {
    try {
      final windows = await WindowController.getAll();
      return windows.any((window) => window.windowId == _controller.windowId);
    } catch (_) {
      // If we cannot tell, assume it is alive: keeping a possibly-dead
      // window costs one missing overlay, recreating a live one leaks a
      // window forever.
      return true;
    }
  }
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
      // A successful creation was memoized forever, so a window that died
      // (crashed engine, closed by the OS) left every later show sending
      // into nothing — no overlay for the rest of the process. Rebuild,
      // but only once the window is confirmed gone: this same catch also
      // covers the overlay engine merely not listening yet, and there is
      // no API to close a window, so rebuilding on a transient error
      // would orphan one permanently.
      final handle = _handle;
      if (handle != null && !await handle.isAlive()) {
        _forgetWindow();
      }
    }
    final isTextPill = variant != OverlayVariant.working;
    driver.show(
      width: isTextPill ? textPillWidth : 210,
      height: isTextPill ? textPillHeightFor(message) : 58,
    );
    if (isTextPill) {
      // Info/error are transient toasts: without this they would sit
      // topmost on screen forever (the native overlays auto-hid too).
      _autoHide = Timer(textPillAutoHideAfter, () {
        _autoHide = null;
        unawaited(hide());
      });
    }
  }

  /// The info/error pill's window width. The capsule inside is capped at
  /// 340 and padded 18 each side, so text wraps at 304.
  static const int textPillWidth = 360;
  static const double _textPillTextWidth = 304;

  /// 10px top and bottom, matching the capsule's padding.
  static const double _textPillVerticalPadding = 20;

  /// The pill renders in a second Flutter engine, so its font metrics can
  /// differ slightly from what we measure here; a line of slack keeps a
  /// rounding difference from clipping the last line.
  static const double _textPillSlack = 8;

  /// Height the window needs for [message].
  ///
  /// It used to be a fixed 92, which the two longest real failure messages
  /// filled exactly — four lines of text plus the padding, with nothing to
  /// spare. One more line of copy, a longer translation, or a larger text
  /// scale would have overflowed and rendered as a pill filling the whole
  /// window, which is precisely the bug the capsule fix removed. Measuring
  /// also keeps Linux honest, where the window IS the capsule (the X11
  /// shape supplies the corners), so a fixed height would show as a slab
  /// of empty colour around a short message.
  static int textPillHeightFor(String message) {
    final painter = TextPainter(
      text: TextSpan(text: message, style: const TextStyle(fontSize: 12.5)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _textPillTextWidth);
    final needed = painter.height + _textPillVerticalPadding + _textPillSlack;
    painter.dispose();
    // Never smaller than the single-line capsule.
    return needed.ceil() < 44 ? 44 : needed.ceil();
  }

  /// Drops the memoized window so the next show rebuilds it. Creation is
  /// memoized to keep one overlay per app; that memo must not outlive the
  /// window it describes.
  void _forgetWindow() {
    _creating = null;
    _handle = null;
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
