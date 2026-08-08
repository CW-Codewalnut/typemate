import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/microphone_settings_store.dart';

void main() {
  test('loads persisted selected microphone when it is available', () async {
    final store = InMemoryMicrophoneSettingsStore('Headset');
    final controller = MicrophoneSettingsController(
      discovery: FakeMicrophoneDiscovery(const [
        MicrophoneDevice(name: 'Built-in'),
        MicrophoneDevice(name: 'Headset'),
      ]),
      store: store,
    );

    await controller.loadMicrophones();

    expect(controller.selectedMicrophone?.name, 'Headset');
  });

  test('saves selected microphone name', () async {
    final store = InMemoryMicrophoneSettingsStore(null);
    final controller = MicrophoneSettingsController(
      discovery: FakeMicrophoneDiscovery(const [
        MicrophoneDevice(name: 'Built-in'),
        MicrophoneDevice(name: 'Headset'),
      ]),
      store: store,
    );

    await controller.loadMicrophones();
    controller.selectMicrophone(const MicrophoneDevice(name: 'Headset'));
    await store.waitForSave();

    expect(store.selectedName, 'Headset');
  });

  test('file store saves and loads selected microphone name', () async {
    final directory = Directory('build/test-settings');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    final store = FileMicrophoneSettingsStore(
      file: File('${directory.path}/settings.json'),
    );

    await store.saveSelectedMicrophoneName('USB Mic');

    expect(await store.loadSelectedMicrophoneName(), 'USB Mic');
  });
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  FakeMicrophoneDiscovery(this.devices);

  final List<MicrophoneDevice> devices;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => devices;
}

class InMemoryMicrophoneSettingsStore implements MicrophoneSettingsStore {
  InMemoryMicrophoneSettingsStore(this.selectedName);

  String? selectedName;
  Future<void>? _lastSave;

  @override
  Future<String?> loadSelectedMicrophoneName() async => selectedName;

  @override
  Future<void> saveSelectedMicrophoneName(String name) {
    selectedName = name;
    _lastSave = Future<void>.value();
    return _lastSave!;
  }

  Future<void> waitForSave() async => _lastSave;
}
