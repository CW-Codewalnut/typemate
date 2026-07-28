import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loadMicrophones stores discovered devices and selects the first one',
    () async {
      final controller = MicrophoneSettingsController(
        discovery: FakeMicrophoneDiscovery([
          const MicrophoneDevice(name: 'Microphone (Brio 100)'),
          const MicrophoneDevice(name: 'Headset (Tribit XSound Go)'),
        ]),
      );

      await controller.loadMicrophones();

      expect(controller.microphones.map((microphone) => microphone.name), [
        'Microphone (Brio 100)',
        'Headset (Tribit XSound Go)',
      ]);
      expect(controller.selectedMicrophone?.name, 'Microphone (Brio 100)');
      expect(controller.statusMessage, '2 microphones found.');
    },
  );

  test('selectMicrophone updates the selected device', () async {
    const headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');
    final controller = MicrophoneSettingsController(
      discovery: FakeMicrophoneDiscovery([
        const MicrophoneDevice(name: 'Microphone (Brio 100)'),
        headset,
      ]),
    );

    await controller.loadMicrophones();
    controller.selectMicrophone(headset);

    expect(controller.selectedMicrophone, headset);
  });

  test(
    'refreshDeviceList picks up new devices and keeps the selection',
    () async {
      const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
      const headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');
      final discovery = FakeMicrophoneDiscovery([brio]);
      final controller = MicrophoneSettingsController(discovery: discovery);
      await controller.loadMicrophones();

      discovery.devices = [brio, headset];
      await controller.refreshDeviceList();

      expect(controller.microphones, [brio, headset]);
      expect(controller.selectedMicrophone, brio);
      expect(controller.statusMessage, '2 microphones found.');
    },
  );

  test('refreshDeviceList falls back when the selected device is '
      'unplugged', () async {
    const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
    const headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');
    final discovery = FakeMicrophoneDiscovery([brio, headset]);
    final controller = MicrophoneSettingsController(discovery: discovery);
    await controller.loadMicrophones();
    controller.selectMicrophone(headset);

    discovery.devices = [brio];
    await controller.refreshDeviceList();

    expect(controller.microphones, [brio]);
    expect(controller.selectedMicrophone, brio);
  });

  test('refreshDeviceList stays silent when nothing changed', () async {
    const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
    final discovery = FakeMicrophoneDiscovery([brio]);
    final controller = MicrophoneSettingsController(discovery: discovery);
    await controller.loadMicrophones();
    var notifications = 0;
    controller.addListener(() => notifications++);

    // A fresh scan returns equal-but-distinct instances; value equality
    // must recognize them as the same devices.
    discovery.devices = [const MicrophoneDevice(name: 'Microphone (Brio 100)')];
    await controller.refreshDeviceList();

    expect(notifications, 0);
  });

  test('a transient scan failure during refresh keeps the working '
      'list', () async {
    const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
    final discovery = FakeMicrophoneDiscovery([brio]);
    final controller = MicrophoneSettingsController(discovery: discovery);
    await controller.loadMicrophones();

    discovery.failure = StateError('device enumeration hiccup');
    await controller.refreshDeviceList();

    expect(controller.microphones, [brio]);
    expect(controller.hasError, isFalse);
  });

  test('startWatchingDevices polls until stopped', () async {
    const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
    const headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');
    final discovery = FakeMicrophoneDiscovery([brio]);
    final controller = MicrophoneSettingsController(discovery: discovery);
    await controller.loadMicrophones();

    controller.startWatchingDevices(interval: const Duration(milliseconds: 20));
    discovery.devices = [brio, headset];
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.microphones, [brio, headset]);

    controller.stopWatchingDevices();
    discovery.devices = [brio];
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.microphones, [brio, headset]);
  });

  test('shows an actionable error when microphone discovery fails', () async {
    final controller = MicrophoneSettingsController(
      discovery: ThrowingMicrophoneDiscovery(),
    );

    await controller.loadMicrophones();

    expect(controller.microphones, isEmpty);
    expect(controller.selectedMicrophone, isNull);
    expect(controller.hasError, isTrue);
    expect(
      controller.statusMessage,
      'Unable to scan microphones. Check the microphone and its permissions, then reopen Settings.',
    );
  });
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  FakeMicrophoneDiscovery(this.devices);

  /// Mutable so tests can simulate plugging or removing devices between
  /// scans; [failure] simulates a transient scan error.
  List<MicrophoneDevice> devices;
  Object? failure;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    if (failure case final error?) {
      throw error;
    }
    return devices;
  }
}

class ThrowingMicrophoneDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    throw StateError('ffmpeg unavailable');
  }
}
