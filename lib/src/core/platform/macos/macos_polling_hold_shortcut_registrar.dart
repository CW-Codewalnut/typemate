import 'dart:async';
import 'dart:ffi';

import '../../hold_shortcut_controller.dart';
import 'macos_key_codes.dart';

/// Reads global key state from the window server. Abstracted so tests can
/// fake key state without CoreGraphics.
abstract interface class MacKeyState {
  bool isKeyDown(int keyCode);

  /// macOS key codes that represent this Windows virtual-key code (both
  /// left and right variants for modifiers), or empty if the key has no
  /// mapping.
  List<int> keyCodesForVirtualKey(int virtualKey);
}

/// Global hold-shortcut detection on macOS by polling
/// CGEventSourceKeyState — the same edge-detection model as the Windows
/// and Linux registrars, so [HoldShortcutOption]s keep their Windows
/// virtual-key codes and this class translates them to macOS key codes.
class MacOSPollingHoldShortcutRegistrar implements HoldShortcutRegistrar {
  MacOSPollingHoldShortcutRegistrar({
    this._pollInterval = const Duration(milliseconds: 25),
    this._keyState,
    HoldShortcutOption? shortcut,
  }) : _shortcut = shortcut ?? holdShortcutOptionById(defaultHoldShortcutId);

  final Duration _pollInterval;

  /// Lazily bound on first registration so constructing the registrar is
  /// safe on any host (tests, non-mac platforms); a binding failure then
  /// surfaces through the controller's error handling.
  MacKeyState? _keyState;

  Timer? _timer;
  ShortcutCallback? _onPressed;
  ShortcutCallback? _onReleased;
  HoldShortcutOption _shortcut;
  List<List<int>> _keyCodeGroups = const [];
  bool _wasPressed = false;
  bool _isHandlingEvent = false;

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    _shortcut = shortcut;
    final keyState = _keyState ??= FfiMacKeyState();
    _keyCodeGroups = _shortcut.virtualKeyCodes
        .map(keyState.keyCodesForVirtualKey)
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
    // A key with no macOS mapping can never satisfy the hold.
    if (_keyCodeGroups.isEmpty ||
        _keyCodeGroups.any((group) => group.isEmpty)) {
      return;
    }

    final keyState = _keyState;
    if (keyState == null) {
      return;
    }
    final isPressed = _keyCodeGroups.every(
      (group) => group.any(keyState.isKeyDown),
    );
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

typedef _CGEventSourceKeyStateNative = Bool Function(Int32, Uint16);
typedef _CGEventSourceKeyState = bool Function(int, int);

/// kCGEventSourceStateCombinedSessionState: the live key state of the
/// login session, which is what "is the user holding the shortcut right
/// now" means.
const _combinedSessionState = 0;

/// Real macOS key state via CoreGraphics.
class FfiMacKeyState implements MacKeyState {
  FfiMacKeyState() {
    final coreGraphics = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    );
    _keyStateFunction = coreGraphics
        .lookupFunction<_CGEventSourceKeyStateNative, _CGEventSourceKeyState>(
          'CGEventSourceKeyState',
        );
  }

  late final _CGEventSourceKeyState _keyStateFunction;

  @override
  bool isKeyDown(int keyCode) =>
      _keyStateFunction(_combinedSessionState, keyCode);

  @override
  List<int> keyCodesForVirtualKey(int virtualKey) =>
      macKeyCodesForVirtualKey(virtualKey);
}
