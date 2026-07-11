import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dictation_controller.dart';

typedef ShortcutCallback = Future<void> Function();

abstract interface class HoldShortcutRegistrar {
  Future<void> registerHoldShortcut({
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  });

  Future<void> unregisterHoldShortcut();
}

class NoopHoldShortcutRegistrar implements HoldShortcutRegistrar {
  const NoopHoldShortcutRegistrar();

  @override
  Future<void> registerHoldShortcut({
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {}

  @override
  Future<void> unregisterHoldShortcut() async {}
}

class HoldShortcutController extends ChangeNotifier {
  HoldShortcutController({
    required this.dictationController,
    required this.registrar,
  });

  final DictationController dictationController;
  final HoldShortcutRegistrar registrar;

  bool _isRegistered = false;
  bool _isPressed = false;
  String _statusMessage = 'Global shortcut not registered.';

  bool get isRegistered => _isRegistered;
  bool get isPressed => _isPressed;
  String get statusMessage => _statusMessage;

  Future<void> register() async {
    try {
      await registrar.registerHoldShortcut(
        onPressed: _handlePressed,
        onReleased: _handleReleased,
      );
      _isRegistered = true;
      _statusMessage = 'Global shortcut ready: hold Ctrl+Alt+Space.';
    } catch (_) {
      _isRegistered = false;
      _statusMessage =
          'Unable to register global shortcut. Use the preview button for now.';
    }
    notifyListeners();
  }

  Future<void> unregister() async {
    await registrar.unregisterHoldShortcut();
    _isRegistered = false;
    _isPressed = false;
    _statusMessage = 'Global shortcut not registered.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(registrar.unregisterHoldShortcut());
    super.dispose();
  }

  Future<void> _handlePressed() async {
    if (_isPressed) {
      return;
    }

    _isPressed = true;
    notifyListeners();
    await dictationController.startListening();
  }

  Future<void> _handleReleased() async {
    if (!_isPressed) {
      return;
    }

    _isPressed = false;
    notifyListeners();
    await dictationController.stopListening();
  }
}
