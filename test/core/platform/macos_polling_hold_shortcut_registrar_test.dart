import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/macos/macos_polling_hold_shortcut_registrar.dart';

class FakeMacosKeyState implements MacosKeyState {
  final Set<int> keyCodesDown = {};
  int accessRequests = 0;

  @override
  bool isKeyDown(int macKeyCode) => keyCodesDown.contains(macKeyCode);

  @override
  bool ensureListenEventAccess() {
    accessRequests += 1;
    return true;
  }
}

void main() {
  test('fires on Ctrl+Command hold and release using macOS keycodes', () async {
    final keyState = FakeMacosKeyState();
    var pressCount = 0;
    var releaseCount = 0;
    final registrar = MacosPollingHoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      keyState: keyState,
    );

    // The default ctrl-win shortcut: Ctrl maps to Control, Win to Command.
    await registrar.registerHoldShortcut(
      shortcut: holdShortcutOptionById(defaultHoldShortcutId),
      onPressed: () async => pressCount += 1,
      onReleased: () async => releaseCount += 1,
    );
    expect(keyState.accessRequests, 1, reason: 'Input Monitoring prompted');

    // Right-hand variants must count too, like GetAsyncKeyState on Windows.
    keyState.keyCodesDown.addAll([0x3E, 0x37]); // right Control + Command
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
    final keyState = FakeMacosKeyState();
    var pressCount = 0;
    final registrar = MacosPollingHoldShortcutRegistrar(
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

  test('maps Windows virtual keys to macOS keycodes', () {
    expect(macosKeyCodesForVirtualKey(0x11), [0x3B, 0x3E]); // Control L/R
    expect(macosKeyCodesForVirtualKey(0x5B), [0x37, 0x36]); // Command L/R
    expect(macosKeyCodesForVirtualKey(0x10), [0x38, 0x3C]); // Shift L/R
    expect(macosKeyCodesForVirtualKey(0x12), [0x3A, 0x3D]); // Option L/R
    expect(macosKeyCodesForVirtualKey(0x78), [0x65]); // F9
    expect(macosKeyCodesForVirtualKey(0x41), [0x00]); // A
    expect(macosKeyCodesForVirtualKey(0x5A), [0x06]); // Z
    expect(macosKeyCodesForVirtualKey(0x30), [0x1D]); // '0'
    expect(macosKeyCodesForVirtualKey(0x39), [0x19]); // '9'
    expect(macosKeyCodesForVirtualKey(0x20), [0x31]); // space
    expect(macosKeyCodesForVirtualKey(0xA5), isEmpty); // unmapped
  });
}
