import 'package:typemate/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses audio devices from ffmpeg dshow device output', () {
    const output = r'''
[in#0 @ 0000023546537a00] "Brio 100" (video)
[in#0 @ 0000023546537a00]   Alternative name "@device_pnp_\\?\usb#vid_046d&pid_094c&mi_00#7&5aade7c&0&0000#{65e8773d-8f56-11d0-a3b9-00a0c9223196}\global"
[in#0 @ 0000023546537a00] "Microphone (Brio 100)" (audio)
[in#0 @ 0000023546537a00]   Alternative name "@device_cm_{33D9A762-90C8-11D0-BD43-00A0C911CE86}\wave_{79BD100C-9ACE-43FE-9839-3D0C45F44B69}"
[in#0 @ 0000023546537a00] "Microphone Array (Intel® Smart Sound Technology for Digital Microphones)" (audio)
[in#0 @ 0000023546537a00]   Alternative name "@device_cm_{33D9A762-90C8-11D0-BD43-00A0C911CE86}\wave_{1906B999-D02F-4207-9CC7-0C0908C25531}"
Error opening input file dummy.
''';

    final devices = FfmpegMicrophoneDiscovery.parseDirectShowDevices(output);

    expect(devices.map((device) => device.name), [
      'Microphone (Brio 100)',
      'Microphone Array (Intel® Smart Sound Technology for Digital Microphones)',
    ]);
    expect(devices.first.alternativeName, contains('wave_'));
  });

  test('list returns parsed devices from the process runner output', () async {
    final discovery = FfmpegMicrophoneDiscovery(
      processRunner: FakeDiscoveryProcessRunner('''
[in#0] "External Mic" (audio)
[in#0]   Alternative name "alt-external"
'''),
    );

    final devices = await discovery.listMicrophones();

    expect(devices.single.name, 'External Mic');
    expect(devices.single.alternativeName, 'alt-external');
  });
}

class FakeDiscoveryProcessRunner implements DiscoveryProcessRunner {
  FakeDiscoveryProcessRunner(this.output);

  final String output;
  String? executable;
  List<String>? arguments;

  @override
  Future<DiscoveryProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = arguments;
    return DiscoveryProcessResult(exitCode: 1, output: output);
  }
}
