import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/platform/mock_platform_bridge.dart';
import 'package:typemate/src/platform/windows_clipboard_paste_platform_bridge.dart';

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
}
