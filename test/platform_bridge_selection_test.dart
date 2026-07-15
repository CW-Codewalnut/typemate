import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows_clipboard_paste_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows_polling_hold_shortcut_registrar.dart';

void main() {
  test('uses Windows clipboard paste bridge on Windows', () {
    expect(
      createDefaultPlatformBridge(isWindows: true),
      isA<WindowsClipboardPastePlatformBridge>(),
    );
  });

  test('uses mock platform bridge on non-Windows platforms', () {
    expect(
      createDefaultPlatformBridge(isWindows: false),
      isA<MockPlatformBridge>(),
    );
  });

  test('uses Windows polling shortcut registrar on Windows', () {
    expect(
      createDefaultHoldShortcutRegistrar(isWindows: true),
      isA<WindowsPollingHoldShortcutRegistrar>(),
    );
  });

  test('uses noop shortcut registrar on non-Windows platforms', () {
    expect(
      createDefaultHoldShortcutRegistrar(isWindows: false),
      isA<NoopHoldShortcutRegistrar>(),
    );
  });
}
