import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/record_package_audio.dart';
import 'package:typemate/src/core/audio/system_default_microphone_discovery.dart';
import 'package:typemate/src/core/platform/linux/linux_platform_bridge.dart';
import 'package:typemate/src/core/platform/linux/linux_x11_hold_shortcut_registrar.dart';
import 'package:typemate/src/core/platform/macos/macos_platform_bridge.dart';
import 'package:typemate/src/core/platform/macos/macos_polling_hold_shortcut_registrar.dart';
import 'package:typemate/src/core/platform/windows/windows_platform_bridge.dart';
import 'package:typemate/src/core/platform/windows/windows_polling_hold_shortcut_registrar.dart';

/// Pins which native adapters the app wires up on the OS this binary is
/// actually running on. Unit tests cover the factories with forced flags;
/// this run proves the real resolution on each CI runner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('default adapters match the operating system of this runner', () {
    final bridge = createDefaultPlatformBridge();
    final registrar = createDefaultHoldShortcutRegistrar();
    final discovery = createDefaultMicrophoneDiscovery();

    if (Platform.isWindows) {
      expect(bridge, isA<WindowsPlatformBridge>());
      expect(registrar, isA<WindowsPollingHoldShortcutRegistrar>());
      expect(discovery, isA<RecordPackageMicrophoneDiscovery>());
    } else if (Platform.isLinux) {
      expect(bridge, isA<LinuxPlatformBridge>());
      expect(registrar, isA<LinuxX11HoldShortcutRegistrar>());
      expect(discovery, isA<SystemDefaultMicrophoneDiscovery>());
    } else if (Platform.isMacOS) {
      expect(bridge, isA<MacosPlatformBridge>());
      expect(registrar, isA<MacosPollingHoldShortcutRegistrar>());
      expect(discovery, isA<RecordPackageMicrophoneDiscovery>());
    } else {
      fail('Unsupported CI operating system: ${Platform.operatingSystem}');
    }
  });
}
