import 'dart:async';
import 'dart:ffi';

import '../core/hold_shortcut_controller.dart';

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 virtualKey);
typedef GetAsyncKeyState = int Function(int virtualKey);

class WindowsPollingHoldShortcutRegistrar implements HoldShortcutRegistrar {
  WindowsPollingHoldShortcutRegistrar({
    this._pollInterval = const Duration(milliseconds: 25),
    this._ctrlTapTimeout = const Duration(milliseconds: 700),
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
  final Duration _ctrlTapTimeout;
  final GetAsyncKeyState _getAsyncKeyState;

  Timer? _timer;
  ShortcutCallback? _onPressed;
  ShortcutCallback? _onReleased;
  HoldShortcutOption _shortcut;
  bool _wasPressed = false;
  bool _isHandlingEvent = false;
  int _ctrlTapCount = 0;
  DateTime? _lastCtrlTapAt;
  bool _isCtrlHoldListening = false;

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
    _resetCtrlSequence();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  Future<void> unregisterHoldShortcut() async {
    _timer?.cancel();
    _timer = null;
    _wasPressed = false;
    _resetCtrlSequence();
    _onPressed = null;
    _onReleased = null;
  }

  void _poll() {
    if (_isHandlingEvent) {
      return;
    }

    if (_shortcut.id == defaultHoldShortcutId) {
      _pollCtrlDoubleTapThenHold();
      return;
    }

    final isPressed = _shortcut.virtualKeyCodes.every(_isKeyDown);
    if (isPressed == _wasPressed) {
      return;
    }

    _wasPressed = isPressed;
    _fire(isPressed ? _onPressed : _onReleased);
  }

  void _pollCtrlDoubleTapThenHold() {
    final isCtrlDown = _isKeyDown(0x11);
    if (isCtrlDown == _wasPressed) {
      return;
    }

    _wasPressed = isCtrlDown;
    final now = DateTime.now();
    if (isCtrlDown) {
      if (_lastCtrlTapAt != null &&
          now.difference(_lastCtrlTapAt!) > _ctrlTapTimeout) {
        _ctrlTapCount = 0;
      }

      if (_ctrlTapCount >= 2) {
        _isCtrlHoldListening = true;
        _fire(_onPressed);
      }
      return;
    }

    if (_isCtrlHoldListening) {
      _fire(_onReleased, onComplete: _resetCtrlSequence);
      return;
    }

    _ctrlTapCount += 1;
    _lastCtrlTapAt = now;
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

  void _resetCtrlSequence() {
    _ctrlTapCount = 0;
    _lastCtrlTapAt = null;
    _isCtrlHoldListening = false;
  }

  bool _isKeyDown(int virtualKey) =>
      (_getAsyncKeyState(virtualKey) & 0x8000) != 0;
}
