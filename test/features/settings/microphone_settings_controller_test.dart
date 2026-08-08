import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/microphone_settings_store.dart';
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

  test('a re-plugged persisted device reclaims the selection from the '
      'fallback', () async {
    const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
    const headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');
    final discovery = FakeMicrophoneDiscovery([brio, headset]);
    final store = MemoryMicrophoneSettingsStore();
    final controller = MicrophoneSettingsController(
      discovery: discovery,
      store: store,
    );
    await controller.loadMicrophones();
    controller.selectMicrophone(headset);
    expect(store.saved, headset.name);

    discovery.devices = [brio];
    await controller.refreshDeviceList();
    expect(controller.selectedMicrophone, brio);
    // The temporary fallback must not overwrite the user's persisted
    // choice.
    expect(store.saved, headset.name);

    discovery.devices = [brio, headset];
    await controller.refreshDeviceList();
    expect(controller.selectedMicrophone, headset);
  });

  test('overlapping refreshes are skipped, not run concurrently', () async {
    const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
    final discovery = FakeMicrophoneDiscovery([brio]);
    final controller = MicrophoneSettingsController(discovery: discovery);
    await controller.loadMicrophones();
    expect(discovery.scanCount, 1);

    final gate = Completer<List<MicrophoneDevice>>();
    discovery.gate = gate;
    final first = controller.refreshDeviceList();
    final second = controller.refreshDeviceList();
    // Only the first tick scanned; the second returned early.
    expect(discovery.scanCount, 2);

    discovery.gate = null;
    gate.complete([brio]);
    await first;
    await second;
    expect(discovery.scanCount, 2);
  });

  test('an empty successful re-scan retires a stale error message', () async {
    final discovery = FakeMicrophoneDiscovery([])
      ..failure = StateError('enumeration broken');
    final controller = MicrophoneSettingsController(discovery: discovery);
    await controller.loadMicrophones();
    expect(controller.hasError, isTrue);

    discovery.failure = null;
    await controller.refreshDeviceList();

    expect(controller.hasError, isFalse);
    expect(controller.statusMessage, 'No microphones found.');
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

  test('startWatchingDevices polls until stopped', () {
    // fakeAsync advances time synchronously so this cannot flake on a
    // slow CI runner.
    fakeAsync((async) {
      const brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
      const headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');
      final discovery = FakeMicrophoneDiscovery([brio]);
      final controller = MicrophoneSettingsController(discovery: discovery);
      controller.loadMicrophones();
      async.flushMicrotasks();

      controller.startWatchingDevices(interval: const Duration(seconds: 2));
      discovery.devices = [brio, headset];
      async.elapse(const Duration(seconds: 2));

      expect(controller.microphones, [brio, headset]);

      controller.stopWatchingDevices();
      discovery.devices = [brio];
      async.elapse(const Duration(seconds: 10));

      expect(controller.microphones, [brio, headset]);
    });
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
  /// scans; [failure] simulates a transient scan error; [gate] makes a
  /// scan hang until completed, to exercise overlap handling.
  List<MicrophoneDevice> devices;
  Object? failure;
  Completer<List<MicrophoneDevice>>? gate;
  int scanCount = 0;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    scanCount++;
    if (failure case final error?) {
      throw error;
    }
    if (gate case final pending?) {
      return pending.future;
    }
    return devices;
  }
}

class MemoryMicrophoneSettingsStore implements MicrophoneSettingsStore {
  String? saved;

  @override
  Future<String?> loadSelectedMicrophoneName() async => saved;

  @override
  Future<void> saveSelectedMicrophoneName(String name) async => saved = name;
}

class ThrowingMicrophoneDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    throw StateError('ffmpeg unavailable');
  }
}
