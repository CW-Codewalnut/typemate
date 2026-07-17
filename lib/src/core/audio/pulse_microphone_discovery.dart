import 'microphone_discovery.dart';

/// Lists PulseAudio capture sources via `pactl` (PipeWire ships a Pulse
/// compatibility layer, so this covers modern Linux desktops and WSLg).
///
/// The device's human-readable description becomes [MicrophoneDevice.name]
/// and the Pulse source name (what ffmpeg's `-f pulse -i` expects) becomes
/// [MicrophoneDevice.alternativeName].
class PulseMicrophoneDiscovery implements MicrophoneDiscovery {
  const PulseMicrophoneDiscovery({
    this.processRunner = const DartDiscoveryProcessRunner(),
  });

  final DiscoveryProcessRunner processRunner;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    final result = await processRunner.run('pactl', ['list', 'sources']);
    if (result.exitCode != 0) {
      return const [];
    }
    return parsePulseSources(result.output);
  }

  static List<MicrophoneDevice> parsePulseSources(String output) {
    final devices = <MicrophoneDevice>[];
    String? sourceName;
    String? description;

    void flush() {
      // Monitor sources are loopbacks of speaker output, not microphones.
      if (sourceName != null && !sourceName!.endsWith('.monitor')) {
        devices.add(
          MicrophoneDevice(
            name: description ?? sourceName!,
            alternativeName: sourceName,
          ),
        );
      }
      sourceName = null;
      description = null;
    }

    for (final line in output.split(RegExp(r'\r?\n'))) {
      if (line.startsWith('Source #')) {
        flush();
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.startsWith('Name: ')) {
        sourceName = trimmed.substring('Name: '.length).trim();
      } else if (trimmed.startsWith('Description: ')) {
        description = trimmed.substring('Description: '.length).trim();
      }
    }
    flush();

    return devices;
  }
}
