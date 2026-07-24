import 'dart:async';
import 'dart:ffi';

import '../../hold_shortcut_controller.dart';

/// Reads global key state from CoreGraphics. Abstracted so tests can fake
/// key state without a Mac.
abstract interface class MacosKeyState {
  /// Whether the hardware key with this macOS keycode is currently down.
  bool isKeyDown(int macKeyCode);

  /// Ensures the app may observe global key state (the Input Monitoring
  /// permission). Prompts the user on first call; returns whether access
  /// is currently granted.
  bool ensureListenEventAccess();
}

/// Global hold-shortcut detection on macOS by polling
/// CGEventSourceKeyState — the same edge-detection model as the Windows
/// GetAsyncKeyState registrar, so [HoldShortcutOption]s keep their Windows
/// virtual-key codes and this class translates them to macOS keycodes.
class MacosPollingHoldShortcutRegistrar implements HoldShortcutRegistrar {
  MacosPollingHoldShortcutRegistrar({
    this._pollInterval = const Duration(milliseconds: 25),
    this._keyState,
    HoldShortcutOption? shortcut,
  }) : _shortcut = shortcut ?? holdShortcutOptionById(defaultHoldShortcutId);

  final Duration _pollInterval;

  /// Lazily bound on first registration so constructing the registrar is
  /// safe off macOS (cross-platform tests) without loading CoreGraphics.
  MacosKeyState? _keyState;

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
    final keyState = _keyState ??= FfiMacosKeyState();
    // Prompts for Input Monitoring on first run. Registration proceeds
    // either way: polling simply sees no keys until the user grants it,
    // and granting takes effect without an app restart.
    keyState.ensureListenEventAccess();
    _keycodeGroups = _shortcut.virtualKeyCodes
        .map(macosKeyCodesForVirtualKey)
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
    if (_keycodeGroups.isEmpty ||
        _keycodeGroups.any((group) => group.isEmpty)) {
      return;
    }

    final keyState = _keyState;
    if (keyState == null) {
      return;
    }
    final isPressed = _keycodeGroups.every(
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

typedef _CGEventSourceKeyStateNative = Uint8 Function(Int32, Uint16);
typedef _CGEventSourceKeyState = int Function(int, int);
typedef _CGListenEventAccessNative = Uint8 Function();
typedef _CGListenEventAccess = int Function();

/// Real macOS key state via CoreGraphics.
class FfiMacosKeyState implements MacosKeyState {
  FfiMacosKeyState() {
    final coreGraphics = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    );
    _keyState = coreGraphics
        .lookupFunction<_CGEventSourceKeyStateNative, _CGEventSourceKeyState>(
          'CGEventSourceKeyState',
        );
    _preflightAccess = coreGraphics
        .lookupFunction<_CGListenEventAccessNative, _CGListenEventAccess>(
          'CGPreflightListenEventAccess',
        );
    _requestAccess = coreGraphics
        .lookupFunction<_CGListenEventAccessNative, _CGListenEventAccess>(
          'CGRequestListenEventAccess',
        );
  }

  late final _CGEventSourceKeyState _keyState;
  late final _CGListenEventAccess _preflightAccess;
  late final _CGListenEventAccess _requestAccess;

  /// kCGEventSourceStateCombinedSessionState: key state for the login
  /// session, which is what the hold shortcut cares about.
  static const _combinedSessionState = 0;

  @override
  bool isKeyDown(int macKeyCode) =>
      _keyState(_combinedSessionState, macKeyCode) != 0;

  @override
  bool ensureListenEventAccess() {
    if (_preflightAccess() != 0) {
      return true;
    }
    return _requestAccess() != 0;
  }
}

/// Maps Windows virtual-key codes (the app's canonical shortcut encoding)
/// to macOS keycodes (Carbon kVK_* values). Modifiers map to both their
/// left and right variants, matching GetAsyncKeyState's combined
/// semantics; the Windows key maps to Command.
List<int> macosKeyCodesForVirtualKey(int virtualKey) {
  const shift = [0x38, 0x3C];
  const control = [0x3B, 0x3E];
  const option = [0x3A, 0x3D];
  const command = [0x37, 0x36];

  switch (virtualKey) {
    case 0x10:
      return shift;
    case 0x11:
      return control;
    case 0x12:
      return option;
    case 0x5B:
    case 0x5C:
      return command;
    case 0x20:
      return const [0x31]; // space
    case 0x0D:
      return const [0x24]; // return
    case 0x09:
      return const [0x30]; // tab
    case 0x1B:
      return const [0x35]; // escape
  }
  // F1..F20 (macOS has no F21-F24 keycodes).
  const functionKeys = [
    0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, // F1-F10
    0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A, // F11-F20
  ];
  if (virtualKey >= 0x70 && virtualKey < 0x70 + functionKeys.length) {
    return [functionKeys[virtualKey - 0x70]];
  }
  // 0-9 (kVK_ANSI digit row).
  const digits = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19];
  if (virtualKey >= 0x30 && virtualKey <= 0x39) {
    return [digits[virtualKey - 0x30]];
  }
  // A-Z (kVK_ANSI letters).
  const letters = [
    0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, // A-J
    0x28, 0x25, 0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, // K-T
    0x20, 0x09, 0x0D, 0x07, 0x10, 0x06, // U-Z
  ];
  if (virtualKey >= 0x41 && virtualKey <= 0x5A) {
    return [letters[virtualKey - 0x41]];
  }
  return const [];
}
