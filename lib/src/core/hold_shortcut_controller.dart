import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dictation_controller.dart';

typedef ShortcutCallback = Future<void> Function();

class HoldShortcutOption {
  const HoldShortcutOption({
    required this.id,
    required this.label,
    required this.virtualKeyCodes,
  });

  final String id;
  final String label;
  final List<int> virtualKeyCodes;
}

const defaultHoldShortcutId = 'ctrl-double-tap-hold';

const holdShortcutOptions = [
  HoldShortcutOption(
    id: defaultHoldShortcutId,
    label: 'Double-tap Ctrl, then hold',
    virtualKeyCodes: [0x11],
  ),
  HoldShortcutOption(
    id: 'ctrl-shift-f9',
    label: 'Ctrl+Shift+F9',
    virtualKeyCodes: [0x11, 0x10, 0x78],
  ),
  HoldShortcutOption(
    id: 'alt-shift-f9',
    label: 'Alt+Shift+F9',
    virtualKeyCodes: [0x12, 0x10, 0x78],
  ),
];

const legacyShortcutIds = {
  'ctrl-alt-space',
  'ctrl-shift-space',
  'alt-shift-space',
  'alt-shift-f9',
};

HoldShortcutOption holdShortcutOptionById(String id) {
  return holdShortcutOptions.firstWhere(
    (shortcut) => shortcut.id == id,
    orElse: () => holdShortcutOptions.firstWhere(
      (shortcut) => shortcut.id == defaultHoldShortcutId,
    ),
  );
}

abstract interface class HoldShortcutSettingsStore {
  Future<String> loadShortcutId();
  Future<void> saveShortcutId(String shortcutId);
}

class NoopHoldShortcutSettingsStore implements HoldShortcutSettingsStore {
  const NoopHoldShortcutSettingsStore();

  @override
  Future<String> loadShortcutId() async => defaultHoldShortcutId;

  @override
  Future<void> saveShortcutId(String shortcutId) async {}
}

class FileHoldShortcutSettingsStore implements HoldShortcutSettingsStore {
  const FileHoldShortcutSettingsStore({required this.file});

  final File file;

  @override
  Future<String> loadShortcutId() async {
    if (!await file.exists()) {
      return defaultHoldShortcutId;
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded case {'shortcutId': final String shortcutId}) {
      if (legacyShortcutIds.contains(shortcutId)) {
        return defaultHoldShortcutId;
      }
      return holdShortcutOptionById(shortcutId).id;
    }

    return defaultHoldShortcutId;
  }

  @override
  Future<void> saveShortcutId(String shortcutId) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'shortcutId': holdShortcutOptionById(shortcutId).id}),
      flush: true,
    );
  }
}

abstract interface class HoldShortcutRegistrar {
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  });

  Future<void> unregisterHoldShortcut();
}

class NoopHoldShortcutRegistrar implements HoldShortcutRegistrar {
  const NoopHoldShortcutRegistrar();

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
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
    this.store = const NoopHoldShortcutSettingsStore(),
  });

  final DictationController dictationController;
  final HoldShortcutRegistrar registrar;
  final HoldShortcutSettingsStore store;

  bool _isRegistered = false;
  bool _isPressed = false;
  String _statusMessage = 'Global shortcut not registered.';
  HoldShortcutOption _shortcut = holdShortcutOptionById(defaultHoldShortcutId);

  bool get isRegistered => _isRegistered;
  bool get isPressed => _isPressed;
  String get statusMessage => _statusMessage;
  HoldShortcutOption get shortcut => _shortcut;

  Future<void> register() async {
    try {
      final loadedShortcutId = await store.loadShortcutId();
      final shortcutId = legacyShortcutIds.contains(loadedShortcutId)
          ? defaultHoldShortcutId
          : loadedShortcutId;
      _shortcut = holdShortcutOptionById(shortcutId);
      if (loadedShortcutId != shortcutId) {
        await store.saveShortcutId(shortcutId);
      }
      await registrar.registerHoldShortcut(
        shortcut: _shortcut,
        onPressed: _handlePressed,
        onReleased: _handleReleased,
      );
      _isRegistered = true;
      _statusMessage = _readyMessageFor(_shortcut);
    } catch (_) {
      _isRegistered = false;
      _statusMessage =
          'Unable to register global shortcut. Use the preview button for now.';
    }
    notifyListeners();
  }

  Future<void> selectShortcut(String shortcutId) async {
    final selected = holdShortcutOptionById(shortcutId);
    if (selected.id == _shortcut.id) {
      return;
    }

    _shortcut = selected;
    await store.saveShortcutId(selected.id);
    if (_isRegistered) {
      await registrar.unregisterHoldShortcut();
      await registrar.registerHoldShortcut(
        shortcut: _shortcut,
        onPressed: _handlePressed,
        onReleased: _handleReleased,
      );
      _statusMessage = _readyMessageFor(_shortcut);
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

  String _readyMessageFor(HoldShortcutOption shortcut) {
    if (shortcut.id == defaultHoldShortcutId) {
      return 'Global shortcut ready: double-tap Ctrl, then hold Ctrl to dictate.';
    }
    return 'Global shortcut ready: hold ${shortcut.label}.';
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
