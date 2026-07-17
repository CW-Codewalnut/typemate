import 'microphone_discovery.dart';

/// Linux microphone discovery without any external tools: recording uses
/// ALSA's `default` device, which PipeWire/PulseAudio route to whichever
/// microphone is selected in the system sound settings. The picker there
/// IS the microphone picker, so the app offers exactly one entry.
class SystemDefaultMicrophoneDiscovery implements MicrophoneDiscovery {
  const SystemDefaultMicrophoneDiscovery();

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    return const [
      MicrophoneDevice(
        name: 'System default microphone',
        alternativeName: 'default',
      ),
    ];
  }
}
