import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/linux_x11_hold_shortcut_registrar.dart';

class FakeX11KeyState implements X11KeyState {
  final Set<int> keycodesDown = {};

  /// Ctrl (VK 0x11) → keycodes 37/105, Super (VK 0x5B) → 133/134,
  /// Alt (VK 0x12) → 64/108, like a standard X keyboard map.
  static const _map = {
    0x11: [37, 105],
    0x5B: [133, 134],
    0x12: [64, 108],
  };

  @override
  List<int> keycodesForVirtualKey(int virtualKey) =>
      _map[virtualKey] ?? const [];

  @override
  Uint8List readKeymap() {
    final keymap = Uint8List(32);
    for (final keycode in keycodesDown) {
      keymap[keycode >> 3] |= 1 << (keycode & 7);
    }
    return keymap;
  }
}

void main() {
  test('fires on Ctrl+Super hold and release using X keycodes', () async {
    final keyState = FakeX11KeyState();
    var pressCount = 0;
    var releaseCount = 0;
    final registrar = LinuxX11HoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      keyState: keyState,
    );

    await registrar.registerHoldShortcut(
      shortcut: holdShortcutOptionById(defaultHoldShortcutId),
      onPressed: () async => pressCount += 1,
      onReleased: () async => releaseCount += 1,
    );

    // Right-hand variants must count too, like GetAsyncKeyState on Windows.
    keyState.keycodesDown.addAll([105, 133]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pressCount, 1);
    expect(releaseCount, 0);

    keyState.keycodesDown.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await registrar.unregisterHoldShortcut();

    expect(pressCount, 1);
    expect(releaseCount, 1);
  });

  test('does not fire when only one key of the combo is held', () async {
    final keyState = FakeX11KeyState();
    var pressCount = 0;
    final registrar = LinuxX11HoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      keyState: keyState,
    );

    await registrar.registerHoldShortcut(
      shortcut: holdShortcutOptionById(defaultHoldShortcutId),
      onPressed: () async => pressCount += 1,
      onReleased: () async {},
    );

    keyState.keycodesDown.add(37);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await registrar.unregisterHoldShortcut();

    expect(pressCount, 0);
  });

  test('maps Windows virtual keys to X11 keysyms', () {
    expect(x11KeysymsForVirtualKey(0x11), [0xFFE3, 0xFFE4]); // Ctrl L/R
    expect(x11KeysymsForVirtualKey(0x5B), [0xFFEB, 0xFFEC]); // Super L/R
    expect(x11KeysymsForVirtualKey(0x78), [0xFFC6]); // F9
    expect(x11KeysymsForVirtualKey(0x41), [0x61]); // A -> 'a'
    expect(x11KeysymsForVirtualKey(0x39), [0x39]); // '9'
    expect(x11KeysymsForVirtualKey(0xA5), isEmpty); // unmapped
  });
}
