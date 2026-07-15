import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/windows_polling_hold_shortcut_registrar.dart';

void main() {
  test(
    'starts listening when Win+Alt is held and stops when released',
    () async {
      final keysDown = <int>{};
      var pressCount = 0;
      var releaseCount = 0;
      final defaultShortcut = holdShortcutOptionById(defaultHoldShortcutId);
      final registrar = WindowsPollingHoldShortcutRegistrar(
        pollInterval: const Duration(milliseconds: 1),
        getAsyncKeyState: (virtualKey) =>
            keysDown.contains(virtualKey) ? 0x8000 : 0,
        shortcut: defaultShortcut,
      );

      await registrar.registerHoldShortcut(
        shortcut: defaultShortcut,
        onPressed: () async => pressCount += 1,
        onReleased: () async => releaseCount += 1,
      );

      keysDown.addAll([0x5B, 0x12]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(pressCount, 1);
      expect(releaseCount, 0);

      keysDown.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await registrar.unregisterHoldShortcut();

      expect(pressCount, 1);
      expect(releaseCount, 1);
    },
  );

  test('does not start listening when only Win is held', () async {
    final keysDown = <int>{};
    var pressCount = 0;
    final defaultShortcut = holdShortcutOptionById(defaultHoldShortcutId);
    final registrar = WindowsPollingHoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      getAsyncKeyState: (virtualKey) =>
          keysDown.contains(virtualKey) ? 0x8000 : 0,
      shortcut: defaultShortcut,
    );

    await registrar.registerHoldShortcut(
      shortcut: defaultShortcut,
      onPressed: () async => pressCount += 1,
      onReleased: () async {},
    );

    keysDown.add(0x5B);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await registrar.unregisterHoldShortcut();
    expect(pressCount, 0);
  });

  test('uses the configured shortcut keys when polling', () async {
    final keysDown = <int>{};
    var pressCount = 0;
    final registrar = WindowsPollingHoldShortcutRegistrar(
      pollInterval: const Duration(milliseconds: 1),
      getAsyncKeyState: (virtualKey) =>
          keysDown.contains(virtualKey) ? 0x8000 : 0,
      shortcut: holdShortcutOptions.firstWhere(
        (shortcut) => shortcut.id == 'ctrl-shift-f9',
      ),
    );

    await registrar.registerHoldShortcut(
      shortcut: holdShortcutOptions.firstWhere(
        (shortcut) => shortcut.id == 'ctrl-shift-f9',
      ),
      onPressed: () async => pressCount += 1,
      onReleased: () async {},
    );

    keysDown.addAll([0x11, 0x10, 0x20]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pressCount, 0);

    keysDown
      ..clear()
      ..addAll([0x11, 0x10, 0x78]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await registrar.unregisterHoldShortcut();
    expect(pressCount, 1);
  });
}
