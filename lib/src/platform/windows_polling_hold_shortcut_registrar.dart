import 'dart:async';
import 'dart:ffi';

import '../core/hold_shortcut_controller.dart';

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 virtualKey);
typedef GetAsyncKeyState = int Function(int virtualKey);

const _vkControl = 0x11;
const _vkMenu = 0x12; // Alt
const _vkSpace = 0x20;

class WindowsPollingHoldShortcutRegistrar implements HoldShortcutRegistrar {
  WindowsPollingHoldShortcutRegistrar({
    this._pollInterval = const Duration(milliseconds: 25),
    GetAsyncKeyState? getAsyncKeyState,
  }) : _getAsyncKeyState =
           getAsyncKeyState ??
           DynamicLibrary.open(
             'user32.dll',
           ).lookupFunction<_GetAsyncKeyStateNative, GetAsyncKeyState>(
             'GetAsyncKeyState',
           );

  final Duration _pollInterval;
  final GetAsyncKeyState _getAsyncKeyState;

  Timer? _timer;
  ShortcutCallback? _onPressed;
  ShortcutCallback? _onReleased;
  bool _wasPressed = false;
  bool _isHandlingEvent = false;

  @override
  Future<void> registerHoldShortcut({
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    _onPressed = onPressed;
    _onReleased = onReleased;
    _timer?.cancel();
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

    final isPressed =
        _isKeyDown(_vkControl) && _isKeyDown(_vkMenu) && _isKeyDown(_vkSpace);
    if (isPressed == _wasPressed) {
      return;
    }

    _wasPressed = isPressed;
    final callback = isPressed ? _onPressed : _onReleased;
    if (callback == null) {
      return;
    }

    _isHandlingEvent = true;
    callback().whenComplete(() => _isHandlingEvent = false);
  }

  bool _isKeyDown(int virtualKey) =>
      (_getAsyncKeyState(virtualKey) & 0x8000) != 0;
}
