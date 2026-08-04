// macOS overlay driver - IN USE but build-verified only (no Mac in the
// development environment); exercise on real hardware before the next
// macOS preview ships.
//
// Approach: the Objective-C runtime via FFI from the main engine styles
// the desktop_multi_window NSWindow to mirror the native Swift
// overlay's semantics - status-level, borderless, non-opaque with a
// clear background (macOS always composits per-pixel alpha, so the
// overlay UI paints Colors.transparent around the pill), shadowless,
// mouse-ignoring, and ordered front WITHOUT ever being made key
// (orderFrontRegardless), which is what keeps focus in the dictation
// target.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../overlay/overlay_window_driver.dart';

typedef _GetClassC = Pointer<Void> Function(Pointer<Utf8>);
typedef _GetClassD = Pointer<Void> Function(Pointer<Utf8>);
typedef _SelC = Pointer<Void> Function(Pointer<Utf8>);
typedef _SelD = Pointer<Void> Function(Pointer<Utf8>);
typedef _MsgPPC = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _MsgPPD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _MsgVoidLongC = Void Function(Pointer<Void>, Pointer<Void>, Int64);
typedef _MsgVoidLongD = void Function(Pointer<Void>, Pointer<Void>, int);
typedef _MsgVoidBoolC = Void Function(Pointer<Void>, Pointer<Void>, Uint8);
typedef _MsgVoidBoolD = void Function(Pointer<Void>, Pointer<Void>, int);
typedef _MsgVoidPtrC =
    Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _MsgVoidPtrD =
    void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _MsgVoidC = Void Function(Pointer<Void>, Pointer<Void>);
typedef _MsgVoidD = void Function(Pointer<Void>, Pointer<Void>);
typedef _MsgUlongC = Uint64 Function(Pointer<Void>, Pointer<Void>);
typedef _MsgUlongD = int Function(Pointer<Void>, Pointer<Void>);
typedef _MsgAtIndexC =
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Uint64);
typedef _MsgAtIndexD =
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int);
typedef _MsgBoolC = Uint8 Function(Pointer<Void>, Pointer<Void>);
typedef _MsgBoolD = int Function(Pointer<Void>, Pointer<Void>);

class MacosOverlayWindowDriver extends OverlayWindowDriver {
  MacosOverlayWindowDriver()
    : _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib'),
      _appKit = DynamicLibrary.open(
        '/System/Library/Frameworks/AppKit.framework/AppKit',
      );

  final DynamicLibrary _objc;
  // AppKit must be loaded for the NSApplication/NSColor classes to
  // resolve; keeping the handle also documents the dependency.
  // ignore: unused_field
  final DynamicLibrary _appKit;

  late final _getClass = _objc.lookupFunction<_GetClassC, _GetClassD>(
    'objc_getClass',
  );
  late final _sel = _objc.lookupFunction<_SelC, _SelD>('sel_registerName');
  late final _msgPP = _objc.lookupFunction<_MsgPPC, _MsgPPD>('objc_msgSend');
  late final _msgVoidLong = _objc.lookupFunction<_MsgVoidLongC, _MsgVoidLongD>(
    'objc_msgSend',
  );
  late final _msgVoidBool = _objc.lookupFunction<_MsgVoidBoolC, _MsgVoidBoolD>(
    'objc_msgSend',
  );
  late final _msgVoidPtr = _objc.lookupFunction<_MsgVoidPtrC, _MsgVoidPtrD>(
    'objc_msgSend',
  );
  late final _msgVoid = _objc.lookupFunction<_MsgVoidC, _MsgVoidD>(
    'objc_msgSend',
  );
  late final _msgUlong = _objc.lookupFunction<_MsgUlongC, _MsgUlongD>(
    'objc_msgSend',
  );
  late final _msgAtIndex = _objc.lookupFunction<_MsgAtIndexC, _MsgAtIndexD>(
    'objc_msgSend',
  );
  late final _msgBool = _objc.lookupFunction<_MsgBoolC, _MsgBoolD>(
    'objc_msgSend',
  );

  Pointer<Void> _cls(String name) {
    final n = name.toNativeUtf8();
    try {
      return _getClass(n.cast());
    } finally {
      malloc.free(n);
    }
  }

  Pointer<Void> _selector(String name) {
    final n = name.toNativeUtf8();
    try {
      return _sel(n.cast());
    } finally {
      malloc.free(n);
    }
  }

  Pointer<Void> _overlayWindow = nullptr;

  /// The main window is [NSApplication.mainWindow]; the overlay is the
  /// other window in [NSApplication.windows] once created.
  Pointer<Void> _findOverlay() {
    final app = _msgPP(_cls('NSApplication'), _selector('sharedApplication'));
    if (app == nullptr) {
      return nullptr;
    }
    final mainWindow = _msgPP(app, _selector('mainWindow'));
    final windows = _msgPP(app, _selector('windows'));
    if (windows == nullptr) {
      return nullptr;
    }
    final count = _msgUlong(windows, _selector('count'));
    for (var i = 0; i < count; i++) {
      final window = _msgAtIndex(windows, _selector('objectAtIndex:'), i);
      if (window != mainWindow && window != nullptr) {
        return window;
      }
    }
    return nullptr;
  }

  @override
  bool adoptNewWindow() {
    final window = _findOverlay();
    if (window == nullptr) {
      return false;
    }
    _overlayWindow = window;
    // Mirror macos/Runner/TypeMateOverlay.swift's panel semantics.
    const nsStatusWindowLevel = 25;
    _msgVoidLong(window, _selector('setLevel:'), nsStatusWindowLevel);
    _msgVoidLong(window, _selector('setStyleMask:'), 0); // borderless
    _msgVoidBool(window, _selector('setOpaque:'), 0);
    _msgVoidBool(window, _selector('setHasShadow:'), 0);
    _msgVoidBool(window, _selector('setIgnoresMouseEvents:'), 1);
    final clear = _msgPP(_cls('NSColor'), _selector('clearColor'));
    _msgVoidPtr(window, _selector('setBackgroundColor:'), clear);
    // canJoinAllSpaces (1) | stationary (16).
    _msgVoidLong(window, _selector('setCollectionBehavior:'), 1 | 16);
    return true;
  }

  @override
  bool show({required int width, required int height}) {
    if (_overlayWindow == nullptr && !adoptNewWindow()) {
      return false;
    }
    // Never makeKey: orderFrontRegardless shows without activation, the
    // same call the native Swift overlay relies on.
    _msgVoid(_overlayWindow, _selector('orderFrontRegardless'));
    return true;
  }

  @override
  void hide() {
    if (_overlayWindow != nullptr) {
      _msgVoidPtr(_overlayWindow, _selector('orderOut:'), nullptr);
    }
  }

  @override
  String focusEvidence() {
    final app = _msgPP(_cls('NSApplication'), _selector('sharedApplication'));
    final key = _msgPP(app, _selector('keyWindow'));
    return 'keyWindow=0x${key.address.toRadixString(16)}';
  }

  @override
  bool get overlayStoleFocus {
    if (_overlayWindow == nullptr) {
      return false;
    }
    return _msgBool(_overlayWindow, _selector('isKeyWindow')) != 0;
  }
}
