import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../hold_shortcut_controller.dart';

/// Reads global key state from the X server. Abstracted so tests can fake
/// keymaps without an X display.
abstract interface class X11KeyState {
  /// 256-bit key-down bitmap from XQueryKeymap (32 bytes, bit per keycode).
  Uint8List readKeymap();

  /// X keycodes that represent this Windows virtual-key code (both left and
  /// right variants for modifiers), or empty if the key has no mapping.
  List<int> keycodesForVirtualKey(int virtualKey);
}

/// Global hold-shortcut detection on X11 by polling the server keymap —
/// the same edge-detection model as the Windows registrar, so
/// [HoldShortcutOption]s keep their Windows virtual-key codes and this
/// class translates them to X keycodes.
class LinuxX11HoldShortcutRegistrar implements HoldShortcutRegistrar {
  LinuxX11HoldShortcutRegistrar({
    this._pollInterval = const Duration(milliseconds: 25),
    this._keyState,
    HoldShortcutOption? shortcut,
  }) : _shortcut = shortcut ?? holdShortcutOptionById(defaultHoldShortcutId);

  final Duration _pollInterval;

  /// Lazily bound on first registration so constructing the registrar is
  /// safe without an X display (headless CI, Wayland-only sessions); the
  /// failure then surfaces through the controller's error handling.
  X11KeyState? _keyState;

  Timer? _timer;
  ShortcutCallback? _onPressed;
  ShortcutCallback? _onReleased;
  HoldShortcutOption _shortcut;
  List<List<int>> _keycodeGroups = const [];
  bool _wasPressed = false;
  bool _isHandlingEvent = false;

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    _shortcut = shortcut;
    final keyState = _keyState ??= FfiX11KeyState();
    _keycodeGroups = _shortcut.virtualKeyCodes
        .map(keyState.keycodesForVirtualKey)
        .toList();
    _onPressed = onPressed;
    _onReleased = onReleased;
    _timer?.cancel();
    _wasPressed = false;
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  Future<void> unregisterHoldShortcut() async {
    _timer?.cancel();
    _timer = null;
    _wasPressed = false;
    _onPressed = null;
    _onReleased = null;
  }

  void _poll() {
    if (_isHandlingEvent) {
      return;
    }
    // A key with no X mapping can never satisfy the hold.
    if (_keycodeGroups.isEmpty ||
        _keycodeGroups.any((group) => group.isEmpty)) {
      return;
    }

    final keyState = _keyState;
    if (keyState == null) {
      return;
    }
    final keymap = keyState.readKeymap();
    bool keycodeDown(int keycode) =>
        keycode > 0 &&
        keycode < 256 &&
        (keymap[keycode >> 3] & (1 << (keycode & 7))) != 0;

    final isPressed = _keycodeGroups.every((group) => group.any(keycodeDown));
    if (isPressed == _wasPressed) {
      return;
    }

    _wasPressed = isPressed;
    _fire(isPressed ? _onPressed : _onReleased);
  }

  void _fire(ShortcutCallback? callback) {
    if (callback == null) {
      return;
    }
    _isHandlingEvent = true;
    callback().whenComplete(() {
      _isHandlingEvent = false;
    });
  }
}

typedef _XOpenDisplayNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplay = Pointer<Void> Function(Pointer<Utf8>);
typedef _XQueryKeymapNative = Int32 Function(Pointer<Void>, Pointer<Uint8>);
typedef _XQueryKeymap = int Function(Pointer<Void>, Pointer<Uint8>);
typedef _XKeysymToKeycodeNative = Uint8 Function(Pointer<Void>, IntPtr);
typedef _XKeysymToKeycode = int Function(Pointer<Void>, int);

/// Real X11 key state via libX11.
class FfiX11KeyState implements X11KeyState {
  FfiX11KeyState() {
    final x11 = DynamicLibrary.open('libX11.so.6');
    _openDisplay = x11.lookupFunction<_XOpenDisplayNative, _XOpenDisplay>(
      'XOpenDisplay',
    );
    _queryKeymap = x11.lookupFunction<_XQueryKeymapNative, _XQueryKeymap>(
      'XQueryKeymap',
    );
    _keysymToKeycode = x11
        .lookupFunction<_XKeysymToKeycodeNative, _XKeysymToKeycode>(
          'XKeysymToKeycode',
        );
    _display = _openDisplay(nullptr);
    if (_display == nullptr) {
      throw StateError(
        'Cannot open the X display. TypeMate needs an X11 session '
        '(or XWayland) for the global hold shortcut.',
      );
    }
    _keymapBuffer = calloc<Uint8>(32);
  }

  late final _XOpenDisplay _openDisplay;
  late final _XQueryKeymap _queryKeymap;
  late final _XKeysymToKeycode _keysymToKeycode;
  late final Pointer<Void> _display;
  late final Pointer<Uint8> _keymapBuffer;

  @override
  Uint8List readKeymap() {
    _queryKeymap(_display, _keymapBuffer);
    return _keymapBuffer.asTypedList(32);
  }

  @override
  List<int> keycodesForVirtualKey(int virtualKey) {
    return [
      for (final keysym in x11KeysymsForVirtualKey(virtualKey))
        _keysymToKeycode(_display, keysym),
    ].where((keycode) => keycode != 0).toList();
  }
}

/// Maps Windows virtual-key codes (the app's canonical shortcut encoding)
/// to X11 keysyms. Modifiers map to both their left and right variants,
/// matching GetAsyncKeyState's combined semantics on Windows.
List<int> x11KeysymsForVirtualKey(int virtualKey) {
  const shift = [0xFFE1, 0xFFE2];
  const control = [0xFFE3, 0xFFE4];
  const alt = [0xFFE9, 0xFFEA];
  const superKey = [0xFFEB, 0xFFEC];

  switch (virtualKey) {
    case 0x10:
      return shift;
    case 0x11:
      return control;
    case 0x12:
      return alt;
    case 0x5B:
    case 0x5C:
      return superKey;
    case 0x20:
      return const [0x0020]; // space
    case 0x0D:
      return const [0xFF0D]; // enter
    case 0x09:
      return const [0xFF09]; // tab
    case 0x1B:
      return const [0xFF1B]; // escape
  }
  // F1..F24
  if (virtualKey >= 0x70 && virtualKey <= 0x87) {
    return [0xFFBE + (virtualKey - 0x70)];
  }
  // 0-9 and A-Z: keysyms are the ASCII codes (letters as lowercase).
  if (virtualKey >= 0x30 && virtualKey <= 0x39) {
    return [virtualKey];
  }
  if (virtualKey >= 0x41 && virtualKey <= 0x5A) {
    return [virtualKey + 0x20];
  }
  return const [];
}
