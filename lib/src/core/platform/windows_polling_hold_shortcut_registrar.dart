import 'dart:async';
import 'dart:ffi';

import '../hold_shortcut_controller.dart';

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 virtualKey);
typedef GetAsyncKeyState = int Function(int virtualKey);

class WindowsPollingHoldShortcutRegistrar implements HoldShortcutRegistrar {
  WindowsPollingHoldShortcutRegistrar({
    this._pollInterval = const Duration(milliseconds: 25),
    GetAsyncKeyState? getAsyncKeyState,
    HoldShortcutOption? shortcut,
  }) : _getAsyncKeyState =
           getAsyncKeyState ??
           DynamicLibrary.open(
             'user32.dll',
           ).lookupFunction<_GetAsyncKeyStateNative, GetAsyncKeyState>(
             'GetAsyncKeyState',
           ),
       _shortcut = shortcut ?? holdShortcutOptionById(defaultHoldShortcutId);

  final Duration _pollInterval;
  final GetAsyncKeyState _getAsyncKeyState;

  Timer? _timer;
  ShortcutCallback? _onPressed;
  ShortcutCallback? _onReleased;
  HoldShortcutOption _shortcut;
  bool _wasPressed = false;
  bool _isHandlingEvent = false;

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    _shortcut = shortcut;
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

    final isPressed = _shortcut.virtualKeyCodes.every(_isKeyDown);
    if (isPressed == _wasPressed) {
      return;
    }

    _wasPressed = isPressed;
    _fire(isPressed ? _onPressed : _onReleased);
  }

  void _fire(ShortcutCallback? callback, {void Function()? onComplete}) {
    if (callback == null) {
      onComplete?.call();
      return;
    }

    _isHandlingEvent = true;
    callback().whenComplete(() {
      onComplete?.call();
      _isHandlingEvent = false;
    });
  }

  bool _isKeyDown(int virtualKey) =>
      (_getAsyncKeyState(virtualKey) & 0x8000) != 0;
}
