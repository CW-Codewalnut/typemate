import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/record_package_audio.dart';
import 'package:typemate/src/core/audio/system_default_microphone_discovery.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/android/android_platform_bridge.dart';
import 'package:typemate/src/core/platform/linux/linux_platform_bridge.dart';
import 'package:typemate/src/core/platform/linux/linux_x11_hold_shortcut_registrar.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows/windows_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows/windows_polling_hold_shortcut_registrar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the Windows bridge on Windows', () {
    expect(
      createDefaultPlatformBridge(isWindows: true, isLinux: false),
      isA<WindowsPlatformBridge>(),
    );
  });

  test('uses the Linux bridge on Linux', () {
    expect(
      createDefaultPlatformBridge(isWindows: false, isLinux: true),
      isA<LinuxPlatformBridge>(),
    );
  });

  // isMacOS is pinned false so the expectation holds on macOS CI runners
  // too, where the unset flag would fall back to Platform.isMacOS.
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
      createDefaultHoldShortcutRegistrar(isWindows: true, isLinux: false),
      isA<WindowsPollingHoldShortcutRegistrar>(),
    );
  });

  test('uses the X11 polling shortcut registrar on Linux', () {
    expect(
      createDefaultHoldShortcutRegistrar(isWindows: false, isLinux: true),
      isA<LinuxX11HoldShortcutRegistrar>(),
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

  test('uses the Android bridge on Android', () {
    expect(
      createDefaultPlatformBridge(
        isWindows: false,
        isLinux: false,
        isMacOS: false,
        isAndroid: true,
      ),
      isA<AndroidPlatformBridge>(),
    );
  });

  test('Android offers the single system default microphone', () {
    expect(
      createDefaultMicrophoneDiscovery(
        isWindows: false,
        isLinux: false,
        isAndroid: true,
      ),
      isA<SystemDefaultMicrophoneDiscovery>(),
    );
  });

  test('Android records the system default device with permission', () {
    final factory = createDefaultAudioRecorderFactory(
      outputDirectory: Directory.systemTemp,
      isWindows: false,
      isLinux: false,
      isAndroid: true,
    );

    expect(factory, isA<RecordPackageAudioRecorderFactory>());
    final recordFactory = factory as RecordPackageAudioRecorderFactory;
    expect(recordFactory.useSystemDefaultDevice, isTrue);
    expect(recordFactory.requestPermission, isTrue);
  });
}
