// X11 overlay driver (Linux): our own Display connection styles the
// overlay window externally - the same technique the native overlay
// binary uses (override-redirect + XShape), which needs no compositor
// and cannot fight GTK's thread: a separate X client may manage any
// window.
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import '../overlay/overlay_window_driver.dart';

typedef _XOpenDisplayC = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplayD = Pointer<Void> Function(Pointer<Utf8>);
typedef _XDisplayFnC = Int32 Function(Pointer<Void>, Int32);
typedef _XDisplayFnD = int Function(Pointer<Void>, int);
typedef _XDefaultScreenC = Int32 Function(Pointer<Void>);
typedef _XDefaultScreenD = int Function(Pointer<Void>);
typedef _XRootWindowC = IntPtr Function(Pointer<Void>, Int32);
typedef _XRootWindowD = int Function(Pointer<Void>, int);
typedef _XQueryTreeC =
    Int32 Function(
      Pointer<Void>,
      IntPtr,
      Pointer<IntPtr>,
      Pointer<IntPtr>,
      Pointer<Pointer<Uint64>>,
      Pointer<Uint32>,
    );
typedef _XQueryTreeD =
    int Function(
      Pointer<Void>,
      int,
      Pointer<IntPtr>,
      Pointer<IntPtr>,
      Pointer<Pointer<Uint64>>,
      Pointer<Uint32>,
    );
typedef _XInternAtomC = IntPtr Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _XInternAtomD = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _XGetWindowPropertyC =
    Int32 Function(
      Pointer<Void>,
      IntPtr,
      IntPtr,
      Int64,
      Int64,
      Int32,
      IntPtr,
      Pointer<IntPtr>,
      Pointer<Int32>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Pointer<Uint8>>,
    );
typedef _XGetWindowPropertyD =
    int Function(
      Pointer<Void>,
      int,
      int,
      int,
      int,
      int,
      int,
      Pointer<IntPtr>,
      Pointer<Int32>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Pointer<Uint8>>,
    );
typedef _XFreeC = Int32 Function(Pointer<Uint8>);
typedef _XFreeD = int Function(Pointer<Uint8>);
typedef _XChangeWindowAttributesC =
    Int32 Function(Pointer<Void>, IntPtr, Uint64, Pointer<Uint8>);
typedef _XChangeWindowAttributesD =
    int Function(Pointer<Void>, int, int, Pointer<Uint8>);
typedef _XMoveResizeWindowC =
    Int32 Function(Pointer<Void>, IntPtr, Int32, Int32, Uint32, Uint32);
typedef _XMoveResizeWindowD =
    int Function(Pointer<Void>, int, int, int, int, int);
typedef _XWindowFnC = Int32 Function(Pointer<Void>, IntPtr);
typedef _XWindowFnD = int Function(Pointer<Void>, int);
typedef _XFlushC = Int32 Function(Pointer<Void>);
typedef _XFlushD = int Function(Pointer<Void>);
typedef _XSyncC = Int32 Function(Pointer<Void>, Int32);
typedef _XSyncD = int Function(Pointer<Void>, int);
typedef _XGetInputFocusC =
    Int32 Function(Pointer<Void>, Pointer<IntPtr>, Pointer<Int32>);
typedef _XGetInputFocusD =
    int Function(Pointer<Void>, Pointer<IntPtr>, Pointer<Int32>);
typedef _XShapeCombineRectanglesC =
    Void Function(
      Pointer<Void>,
      IntPtr,
      Int32,
      Int32,
      Int32,
      Pointer<Int16>,
      Int32,
      Int32,
      Int32,
    );
typedef _XShapeCombineRectanglesD =
    void Function(
      Pointer<Void>,
      int,
      int,
      int,
      int,
      Pointer<Int16>,
      int,
      int,
      int,
    );

class X11OverlayWindowDriver extends OverlayWindowDriver {
  X11OverlayWindowDriver()
    : _x11 = DynamicLibrary.open('libX11.so.6'),
      _xext = DynamicLibrary.open('libXext.so.6') {
    final displayName = Platform.environment['DISPLAY'] ?? ':0';
    final name = displayName.toNativeUtf8();
    try {
      _display = _x11.lookupFunction<_XOpenDisplayC, _XOpenDisplayD>(
        'XOpenDisplay',
      )(name.cast());
    } finally {
      malloc.free(name);
    }
  }

  final DynamicLibrary _x11;
  final DynamicLibrary _xext;
  late final Pointer<Void> _display;
  int _overlayWindow = 0;
  Set<int> _before = {};

  late final _queryTree = _x11.lookupFunction<_XQueryTreeC, _XQueryTreeD>(
    'XQueryTree',
  );
  late final _rootWindow = _x11.lookupFunction<_XRootWindowC, _XRootWindowD>(
    'XRootWindow',
  );
  late final _defaultScreen = _x11
      .lookupFunction<_XDefaultScreenC, _XDefaultScreenD>('XDefaultScreen');
  late final _displayWidth = _x11.lookupFunction<_XDisplayFnC, _XDisplayFnD>(
    'XDisplayWidth',
  );
  late final _displayHeight = _x11.lookupFunction<_XDisplayFnC, _XDisplayFnD>(
    'XDisplayHeight',
  );
  late final _internAtom = _x11.lookupFunction<_XInternAtomC, _XInternAtomD>(
    'XInternAtom',
  );
  late final _getWindowProperty = _x11
      .lookupFunction<_XGetWindowPropertyC, _XGetWindowPropertyD>(
        'XGetWindowProperty',
      );
  late final _xFree = _x11.lookupFunction<_XFreeC, _XFreeD>('XFree');
  late final _changeWindowAttributes = _x11
      .lookupFunction<_XChangeWindowAttributesC, _XChangeWindowAttributesD>(
        'XChangeWindowAttributes',
      );
  late final _moveResizeWindow = _x11
      .lookupFunction<_XMoveResizeWindowC, _XMoveResizeWindowD>(
        'XMoveResizeWindow',
      );
  late final _mapRaised = _x11.lookupFunction<_XWindowFnC, _XWindowFnD>(
    'XMapRaised',
  );
  late final _unmapWindow = _x11.lookupFunction<_XWindowFnC, _XWindowFnD>(
    'XUnmapWindow',
  );
  late final _flush = _x11.lookupFunction<_XFlushC, _XFlushD>('XFlush');
  late final _sync = _x11.lookupFunction<_XSyncC, _XSyncD>('XSync');
  late final _getInputFocus = _x11
      .lookupFunction<_XGetInputFocusC, _XGetInputFocusD>('XGetInputFocus');
  late final _shapeCombineRectangles = _xext
      .lookupFunction<_XShapeCombineRectanglesC, _XShapeCombineRectanglesD>(
        'XShapeCombineRectangles',
      );

  bool get isAvailable => _display != nullptr;

  @override
  bool get needsVisibleAtLaunch => true;

  /// All client windows (recursively) owned by this process. Reparenting
  /// window managers nest the client window inside a frame, so the walk
  /// descends a few levels instead of trusting root's direct children.
  Set<int> _pidWindows() {
    final result = <int>{};
    if (!isAvailable) {
      return result;
    }
    final screen = _defaultScreen(_display);
    final root = _rootWindow(_display, screen);
    final pidAtomName = '_NET_WM_PID'.toNativeUtf8();
    final pidAtom = _internAtom(_display, pidAtomName.cast(), 0);
    malloc.free(pidAtomName);

    void walk(int window, int depth) {
      if (depth > 3) {
        return;
      }
      final rootReturn = malloc<IntPtr>();
      final parentReturn = malloc<IntPtr>();
      final childrenReturn = malloc<Pointer<Uint64>>();
      final countReturn = malloc<Uint32>();
      try {
        if (_queryTree(
              _display,
              window,
              rootReturn,
              parentReturn,
              childrenReturn,
              countReturn,
            ) ==
            0) {
          return;
        }
        final children = childrenReturn.value;
        final count = countReturn.value;
        for (var i = 0; i < count; i++) {
          final child = children[i];
          if (_windowPid(child, pidAtom) == pid) {
            result.add(child);
          }
          walk(child, depth + 1);
        }
        if (children != nullptr) {
          _xFree(children.cast());
        }
      } finally {
        malloc.free(rootReturn);
        malloc.free(parentReturn);
        malloc.free(childrenReturn);
        malloc.free(countReturn);
      }
    }

    walk(root, 0);
    return result;
  }

  int _windowPid(int window, int pidAtom) {
    final actualType = malloc<IntPtr>();
    final actualFormat = malloc<Int32>();
    final itemCount = malloc<Uint64>();
    final bytesAfter = malloc<Uint64>();
    final data = malloc<Pointer<Uint8>>();
    try {
      const xaCardinal = 6;
      final status = _getWindowProperty(
        _display,
        window,
        pidAtom,
        0,
        1,
        0,
        xaCardinal,
        actualType,
        actualFormat,
        itemCount,
        bytesAfter,
        data,
      );
      if (status != 0 || itemCount.value == 0 || data.value == nullptr) {
        return -1;
      }
      final value = data.value.cast<Uint32>().value;
      _xFree(data.value);
      return value;
    } finally {
      malloc.free(actualType);
      malloc.free(actualFormat);
      malloc.free(itemCount);
      malloc.free(bytesAfter);
      malloc.free(data);
    }
  }

  @override
  void snapshotBefore() => _before = _pidWindows();

  /// More than one client window for this pid means the overlay window
  /// already exists, i.e. this is the secondary engine.
  @override
  bool get isSecondaryEngine => _pidWindows().length > 1;

  /// Finds the window created since [snapshotBefore], unmaps it, and
  /// marks it override-redirect so the window manager never decorates,
  /// focuses, or restacks it - the native overlay's exact behaviour.
  @override
  bool adoptNewWindow() {
    final fresh = _pidWindows().difference(_before);
    if (fresh.isEmpty) {
      return false;
    }
    _overlayWindow = fresh.first;
    _unmapWindow(_display, _overlayWindow);
    _sync(_display, 0);
    // XSetWindowAttributes.override_redirect: Bool at byte offset 88 on
    // LP64 (fields before it: 2 pixmaps, 2 ulongs, 3 ints + pad, 2
    // ulongs, Bool save_under + pad, 2 longs).
    const attrsSize = 112;
    const overrideRedirectOffset = 88;
    final attrs = malloc.allocate<Uint8>(attrsSize);
    for (var i = 0; i < attrsSize; i++) {
      attrs[i] = 0;
    }
    attrs.cast<Int32>()[overrideRedirectOffset ~/ 4] = 1;
    const cwOverrideRedirect = 1 << 9;
    _changeWindowAttributes(
      _display,
      _overlayWindow,
      cwOverrideRedirect,
      attrs,
    );
    malloc.free(attrs);
    _sync(_display, 0);
    return true;
  }

  /// Positions bottom-centre, shapes to a rounded pill (per-row spans of
  /// a rounded rect: cutout transparency, no compositor required), and
  /// maps WITHOUT focus - override-redirect windows bypass the WM, so
  /// input focus stays wherever it was.
  @override
  bool show({required int width, required int height}) {
    if (_overlayWindow == 0) {
      return false;
    }
    final screen = _defaultScreen(_display);
    final x = (_displayWidth(_display, screen) - width) ~/ 2;
    final y = _displayHeight(_display, screen) - height - 96;
    _moveResizeWindow(_display, _overlayWindow, x, y, width, height);
    _applyPillShape(width, height);
    _mapRaised(_display, _overlayWindow);
    _flush(_display);
    return true;
  }

  void _applyPillShape(int width, int height) {
    final radius = math.min(29, height ~/ 2);
    final spans = <int>[];
    for (var row = 0; row < height; row++) {
      int inset;
      if (row < radius) {
        final dy = radius - row - 0.5;
        inset = (radius - math.sqrt(radius * radius - dy * dy)).ceil();
      } else if (row >= height - radius) {
        final dy = row - (height - radius) + 0.5;
        inset = (radius - math.sqrt(radius * radius - dy * dy)).ceil();
      } else {
        inset = 0;
      }
      spans
        ..add(inset)
        ..add(row)
        ..add(width - 2 * inset)
        ..add(1);
    }
    // XRectangle is {short x, y; unsigned short width, height}.
    final count = spans.length ~/ 4;
    final buffer = malloc.allocate<Int16>(spans.length * 2);
    for (var i = 0; i < spans.length; i++) {
      buffer[i] = spans[i];
    }
    const shapeBounding = 0;
    const shapeSet = 0;
    const unsorted = 0;
    _shapeCombineRectangles(
      _display,
      _overlayWindow,
      shapeBounding,
      0,
      0,
      buffer,
      count,
      shapeSet,
      unsorted,
    );
    malloc.free(buffer);
  }

  @override
  void hide() {
    if (_overlayWindow != 0) {
      _unmapWindow(_display, _overlayWindow);
      _flush(_display);
    }
  }

  @override
  String focusEvidence() {
    final focus = malloc<IntPtr>();
    final revert = malloc<Int32>();
    try {
      _getInputFocus(_display, focus, revert);
      return 'focus=0x${focus.value.toRadixString(16)}';
    } finally {
      malloc.free(focus);
      malloc.free(revert);
    }
  }

  @override
  bool get overlayStoleFocus {
    final focus = malloc<IntPtr>();
    final revert = malloc<Int32>();
    try {
      _getInputFocus(_display, focus, revert);
      return focus.value == _overlayWindow;
    } finally {
      malloc.free(focus);
      malloc.free(revert);
    }
  }
}
