import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/platform/windows_polling_hold_shortcut_registrar.dart';

void main() {
  test(
    'fires press once while shortcut is held and release when lifted',
    () async {
      final keysDown = <int>{};
      var pressCount = 0;
      var releaseCount = 0;
      final registrar = WindowsPollingHoldShortcutRegistrar(
        pollInterval: const Duration(milliseconds: 1),
        getAsyncKeyState: (virtualKey) =>
            keysDown.contains(virtualKey) ? 0x8000 : 0,
      );

      await registrar.registerHoldShortcut(
        onPressed: () async => pressCount += 1,
        onReleased: () async => releaseCount += 1,
      );

      keysDown.addAll([0x11, 0x12, 0x20]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      keysDown.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await registrar.unregisterHoldShortcut();

      expect(pressCount, 1);
      expect(releaseCount, 1);
    },
  );
}
