import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/macos/macos_key_codes.dart';
import 'package:typemate/src/core/platform/macos/macos_polling_hold_shortcut_registrar.dart';

class FakeMacKeyState implements MacKeyState {
  final Set<int> keyCodesDown = {};

  @override
  bool isKeyDown(int keyCode) => keyCodesDown.contains(keyCode);

  @override
  List<int> keyCodesForVirtualKey(int virtualKey) =>
      macKeyCodesForVirtualKey(virtualKey);
}

void main() {
  test('fires on Ctrl+Cmd hold and release using macOS key codes', () async {
    final keyState = FakeMacKeyState();
    var pressCount = 0;
    var releaseCount = 0;
    final registrar = MacOSPollingHoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      keyState: keyState,
    );

    await registrar.registerHoldShortcut(
      shortcut: holdShortcutOptionById(defaultHoldShortcutId),
      onPressed: () async => pressCount += 1,
      onReleased: () async => releaseCount += 1,
    );

    // Right-hand variants must count too, like GetAsyncKeyState on Windows:
    // right Control (0x3E) + right Command (0x36).
    keyState.keyCodesDown.addAll([0x3E, 0x36]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pressCount, 1);
    expect(releaseCount, 0);

    keyState.keyCodesDown.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await registrar.unregisterHoldShortcut();

    expect(pressCount, 1);
    expect(releaseCount, 1);
  });

  test('does not fire when only one key of the combo is held', () async {
    final keyState = FakeMacKeyState();
    var pressCount = 0;
    final registrar = MacOSPollingHoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      keyState: keyState,
    );

    await registrar.registerHoldShortcut(
      shortcut: holdShortcutOptionById(defaultHoldShortcutId),
      onPressed: () async => pressCount += 1,
      onReleased: () async {},
    );

    keyState.keyCodesDown.add(0x3B); // left Control only
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await registrar.unregisterHoldShortcut();

    expect(pressCount, 0);
  });

  test('maps Windows virtual keys to macOS key codes', () {
    expect(macKeyCodesForVirtualKey(0x11), [0x3B, 0x3E]); // Control L/R
    expect(macKeyCodesForVirtualKey(0x5B), [0x37, 0x36]); // Command L/R
    expect(macKeyCodesForVirtualKey(0x12), [0x3A, 0x3D]); // Option L/R
    expect(macKeyCodesForVirtualKey(0x78), [0x65]); // F9
    expect(macKeyCodesForVirtualKey(0x41), [0x00]); // A
    expect(macKeyCodesForVirtualKey(0x39), [0x19]); // '9'
    expect(macKeyCodesForVirtualKey(0x20), [0x31]); // space
    expect(macKeyCodesForVirtualKey(0x87), isEmpty); // F24: no mac key code
    expect(macKeyCodesForVirtualKey(0xA5), isEmpty); // unmapped
  });
}
