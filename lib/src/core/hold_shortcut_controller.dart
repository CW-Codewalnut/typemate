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
    this.isDefaultGesture = false,
  });

  final String id;
  final String label;
  final List<int> virtualKeyCodes;
  final bool isDefaultGesture;
}

const defaultHoldShortcutId = 'ctrl-win';

const holdShortcutOptions = [
  HoldShortcutOption(
    id: defaultHoldShortcutId,
    label: 'Ctrl+Win',
    virtualKeyCodes: [0x11, 0x5B],
  ),
  HoldShortcutOption(
    id: 'win-alt',
    label: 'Win+Alt',
    virtualKeyCodes: [0x5B, 0x12],
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

/// Shortcut ids that were offered by older builds and are migrated to the
/// default on load. Every id here MUST be absent from [holdShortcutOptions]:
/// listing a live option makes it unsavable, because the load path rewrites
/// it to the default on the next launch. ('alt-shift-f9' was in both, so
/// picking it silently reset on every restart.)
const legacyShortcutIds = {
  'ctrl-double-tap-hold',
  'ctrl-shift',
  'ctrl',
  'ctrl-alt-space',
  'ctrl-shift-space',
  'alt-shift-space',
};

const customShortcutIdPrefix = 'custom:';

HoldShortcutOption holdShortcutOptionById(String id) {
  if (id.startsWith(customShortcutIdPrefix)) {
    return _customShortcutFromId(id);
  }

  return holdShortcutOptions.firstWhere(
    (shortcut) => shortcut.id == id,
    orElse: () => holdShortcutOptions.firstWhere(
      (shortcut) => shortcut.id == defaultHoldShortcutId,
    ),
  );
}

HoldShortcutOption customHoldShortcutOption(List<int> virtualKeyCodes) {
  final normalized = _normalizedVirtualKeyCodes(virtualKeyCodes);
  return HoldShortcutOption(
    id: '$customShortcutIdPrefix${normalized.join('-')}',
    label: labelForVirtualKeyCodes(normalized),
    virtualKeyCodes: normalized,
  );
}

String labelForVirtualKeyCodes(List<int> virtualKeyCodes) {
  return _normalizedVirtualKeyCodes(
    virtualKeyCodes,
  ).map(_labelForVirtualKeyCode).join('+');
}

HoldShortcutOption _customShortcutFromId(String id) {
  final keyCodes = id
      .substring(customShortcutIdPrefix.length)
      .split('-')
      .map(int.tryParse)
      .whereType<int>()
      .toList();
  // Anything unusable falls back to the default, including a custom
  // shortcut written by a build that predates the recorder's validation
  // (or a hand-edited settings file). Validating only where shortcuts are
  // recorded would leave `custom:65` on disk binding dictation to the A
  // key on every launch, with no way to type out of it.
  if (keyCodes.isEmpty || holdShortcutRejectionReason(keyCodes) != null) {
    return holdShortcutOptionById(defaultHoldShortcutId);
  }
  return customHoldShortcutOption(keyCodes);
}

/// Ctrl, Shift, Alt, and the two Windows keys.
const holdShortcutModifierKeyCodes = [0x11, 0x10, 0x12, 0x5B, 0x5C];

/// Combinations the OS (or every app) needs for itself. Binding hold-to-talk
/// to one of these takes the behaviour away system-wide.
const _reservedShortcuts = {
  [0x11, 0x43], // Ctrl+C
  [0x11, 0x56], // Ctrl+V
  [0x11, 0x58], // Ctrl+X
  [0x11, 0x5A], // Ctrl+Z
  [0x11, 0x41], // Ctrl+A
  [0x12, 0x09], // Alt+Tab
  [0x12, 0x73], // Alt+F4
  [0x11, 0x1B], // Ctrl+Esc
};

/// Why [virtualKeyCodes] cannot be a hold shortcut, or null if it can.
///
/// The hold shortcut is polled globally, so a single unmodified key turns
/// every press of that key anywhere on the system into a dictation — and
/// the user cannot type their way to Settings to undo it, because typing
/// is what triggers it. A modifier plus at least one more key is the
/// minimum that leaves the keyboard usable.
String? holdShortcutRejectionReason(List<int> virtualKeyCodes) {
  final keyCodes = _normalizedVirtualKeyCodes(virtualKeyCodes);
  if (keyCodes.length < 2) {
    return 'Use at least two keys, including a modifier like Ctrl or Alt.';
  }
  if (!keyCodes.any(holdShortcutModifierKeyCodes.contains)) {
    return 'Include a modifier key like Ctrl, Shift, Alt, or Windows.';
  }
  for (final reserved in _reservedShortcuts) {
    if (keyCodes.length == reserved.length &&
        _normalizedVirtualKeyCodes(reserved).join('-') == keyCodes.join('-')) {
      return '${labelForVirtualKeyCodes(keyCodes)} is reserved by the system.';
    }
  }
  return null;
}

List<int> _normalizedVirtualKeyCodes(List<int> virtualKeyCodes) {
  final deduped = virtualKeyCodes.toSet().toList();
  const modifierOrder = holdShortcutModifierKeyCodes;
  deduped.sort((left, right) {
    final leftModifierIndex = modifierOrder.indexOf(left);
    final rightModifierIndex = modifierOrder.indexOf(right);
    if (leftModifierIndex != -1 || rightModifierIndex != -1) {
      return (leftModifierIndex == -1 ? 999 : leftModifierIndex).compareTo(
        rightModifierIndex == -1 ? 999 : rightModifierIndex,
      );
    }
    return left.compareTo(right);
  });
  return deduped;
}

String _labelForVirtualKeyCode(int virtualKeyCode) {
  return switch (virtualKeyCode) {
    0x08 => 'Backspace',
    0x09 => 'Tab',
    0x0D => 'Enter',
    0x10 => 'Shift',
    0x11 => 'Ctrl',
    0x12 => 'Alt',
    0x1B => 'Esc',
    0x20 => 'Space',
    0x25 => 'Left',
    0x26 => 'Up',
    0x27 => 'Right',
    0x28 => 'Down',
    0x2E => 'Delete',
    0x5B || 0x5C => 'Win',
    >= 0x30 && <= 0x39 => String.fromCharCode(virtualKeyCode),
    >= 0x41 && <= 0x5A => String.fromCharCode(virtualKeyCode),
    >= 0x70 && <= 0x87 => 'F${virtualKeyCode - 0x6F}',
    _ => 'Key $virtualKeyCode',
  };
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
          'Unable to register global shortcut. Check shortcut settings and try again.';
    }
    notifyListeners();
  }

  Future<void> selectShortcut(String shortcutId) async {
    await selectShortcutOption(holdShortcutOptionById(shortcutId));
  }

  /// Applies [selected], or leaves the current shortcut untouched and
  /// reports why in [statusMessage]. Callers can tell the two apart by
  /// comparing [shortcut] afterwards; this never throws.
  Future<void> selectShortcutOption(HoldShortcutOption selected) async {
    if (selected.id == _shortcut.id) {
      return;
    }

    // The last gate before a shortcut goes live. The recorder UI checks
    // too, but every other caller (a settings id, a restored value) would
    // otherwise reach the registrar unvalidated.
    final rejection = holdShortcutRejectionReason(selected.virtualKeyCodes);
    if (rejection != null) {
      _statusMessage = rejection;
      notifyListeners();
      return;
    }

    final previous = _shortcut;
    try {
      await store.saveShortcutId(selected.id);
      if (_isRegistered) {
        await registrar.unregisterHoldShortcut();
        await registrar.registerHoldShortcut(
          shortcut: selected,
          onPressed: _handlePressed,
          onReleased: _handleReleased,
        );
      }
      // Only after the new shortcut is actually live: assigning first made
      // a failed re-register look like a success to anyone reading
      // `shortcut`, and the throw escaped into an unhandled Future error.
      _shortcut = selected;
      if (_isRegistered) {
        _statusMessage = _readyMessageFor(_shortcut);
      }
    } catch (error) {
      debugPrint('TypeMate: unable to apply shortcut ${selected.id}: $error');
      // Put the previous shortcut back so the user is not left with no
      // working hold key at all.
      _shortcut = previous;
      try {
        await store.saveShortcutId(previous.id);
        if (_isRegistered) {
          await registrar.registerHoldShortcut(
            shortcut: previous,
            onPressed: _handlePressed,
            onReleased: _handleReleased,
          );
        }
        _statusMessage =
            'Could not apply ${selected.label}. Still using '
            '${previous.label}.';
      } catch (_) {
        _isRegistered = false;
        _statusMessage =
            'Could not apply ${selected.label}, and the previous shortcut '
            'could not be restored. Try again from shortcut settings.';
      }
    }
    notifyListeners();
  }

  Future<void> resetShortcutToDefault() async {
    await selectShortcut(defaultHoldShortcutId);
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
