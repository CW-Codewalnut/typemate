import 'package:dictation_flow/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:dictation_flow/src/core/microphone_settings_controller.dart';
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
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  FakeMicrophoneDiscovery(this.devices);

  final List<MicrophoneDevice> devices;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => devices;
}
