import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/linux/linux_platform_bridge.dart';
import 'package:typemate/src/core/platform/linux/linux_x11_hold_shortcut_registrar.dart';
import 'package:typemate/src/core/platform/macos/macos_platform_bridge.dart';
import 'package:typemate/src/core/platform/macos/macos_polling_hold_shortcut_registrar.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows/windows_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows/windows_polling_hold_shortcut_registrar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the Windows bridge on Windows', () {
    expect(
      createDefaultPlatformBridge(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
      ),
      isA<WindowsPlatformBridge>(),
    );
  });

  test('uses the Linux bridge on Linux', () {
    expect(
      createDefaultPlatformBridge(
        isWindows: false,
        isLinux: true,
        isMacOS: false,
      ),
      isA<LinuxPlatformBridge>(),
    );
  });

  test('uses the macOS bridge on macOS', () {
    expect(
      createDefaultPlatformBridge(
        isWindows: false,
        isLinux: false,
        isMacOS: true,
      ),
      isA<MacOSPlatformBridge>(),
    );
  });

  test('uses the mock bridge on unsupported platforms', () {
    expect(
      createDefaultPlatformBridge(
        isWindows: false,
        isLinux: false,
        isMacOS: false,
      ),
      isA<MockPlatformBridge>(),
    );
  });

  test('uses the Windows polling shortcut registrar on Windows', () {
    expect(
      createDefaultHoldShortcutRegistrar(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
      ),
      isA<WindowsPollingHoldShortcutRegistrar>(),
    );
  });

  test('uses the X11 polling shortcut registrar on Linux', () {
    expect(
      createDefaultHoldShortcutRegistrar(
        isWindows: false,
        isLinux: true,
        isMacOS: false,
      ),
      isA<LinuxX11HoldShortcutRegistrar>(),
    );
  });

  test('uses the macOS polling shortcut registrar on macOS', () {
    expect(
      createDefaultHoldShortcutRegistrar(
        isWindows: false,
        isLinux: false,
        isMacOS: true,
      ),
      isA<MacOSPollingHoldShortcutRegistrar>(),
    );
  });

  test('uses the noop shortcut registrar on unsupported platforms', () {
    expect(
      createDefaultHoldShortcutRegistrar(
        isWindows: false,
        isLinux: false,
        isMacOS: false,
      ),
      isA<NoopHoldShortcutRegistrar>(),
    );
  });
}
