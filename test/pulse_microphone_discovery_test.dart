import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/core/audio/pulse_microphone_discovery.dart';

const _pactlOutput = '''
Source #55
	State: SUSPENDED
	Name: alsa_output.pci-0000_00_1f.3.analog-stereo.monitor
	Description: Monitor of Built-in Audio Analog Stereo
	Driver: PipeWire

Source #56
	State: RUNNING
	Name: alsa_input.usb-Logitech_Brio_100-02.mono-fallback
	Description: Brio 100 Mono
	Driver: PipeWire

Source #57
	State: IDLE
	Name: alsa_input.pci-0000_00_1f.3.analog-stereo
	Description: Built-in Audio Analog Stereo
	Driver: PipeWire
''';

void main() {
  test('parses pulse sources and drops monitor loopbacks', () {
    final devices = PulseMicrophoneDiscovery.parsePulseSources(_pactlOutput);

    expect(devices, hasLength(2));
    expect(devices[0].name, 'Brio 100 Mono');
    expect(
      devices[0].alternativeName,
      'alsa_input.usb-Logitech_Brio_100-02.mono-fallback',
    );
    expect(devices[1].name, 'Built-in Audio Analog Stereo');
    expect(
      devices[1].alternativeName,
      'alsa_input.pci-0000_00_1f.3.analog-stereo',
    );
  });

  test('listMicrophones runs pactl and returns parsed devices', () async {
    final discovery = PulseMicrophoneDiscovery(
      processRunner: FakeDiscoveryProcessRunner(
        expectedExecutable: 'pactl',
        expectedArguments: const ['list', 'sources'],
        result: const DiscoveryProcessResult(exitCode: 0, output: _pactlOutput),
      ),
    );

    final devices = await discovery.listMicrophones();
    expect(devices.map((device) => device.name), [
      'Brio 100 Mono',
      'Built-in Audio Analog Stereo',
    ]);
  });

  test('returns no devices when pactl is unavailable', () async {
    final discovery = PulseMicrophoneDiscovery(
      processRunner: FakeDiscoveryProcessRunner(
        expectedExecutable: 'pactl',
        expectedArguments: const ['list', 'sources'],
        result: const DiscoveryProcessResult(exitCode: 1, output: ''),
      ),
    );

    expect(await discovery.listMicrophones(), isEmpty);
  });
}

class FakeDiscoveryProcessRunner implements DiscoveryProcessRunner {
  FakeDiscoveryProcessRunner({
    required this.expectedExecutable,
    required this.expectedArguments,
    required this.result,
  });

  final String expectedExecutable;
  final List<String> expectedArguments;
  final DiscoveryProcessResult result;

  @override
  Future<DiscoveryProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    expect(executable, expectedExecutable);
    expect(arguments, expectedArguments);
    return result;
  }
}
