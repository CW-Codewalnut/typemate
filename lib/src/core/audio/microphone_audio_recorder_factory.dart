import 'dart:io';

import 'audio_recorder.dart';
import 'ffmpeg_audio_recorder.dart';
import 'linux_alsa_device.dart';
import 'microphone_discovery.dart';

export 'ffmpeg_audio_recorder.dart' show RecorderProcess, RecorderProcessRunner;

abstract interface class AudioRecorderFactory {
  AudioRecorder create(MicrophoneDevice microphone);
}

/// Builds ffmpeg-based ALSA recorders for Linux; Windows and macOS record
/// through the record plugin instead.
class MicrophoneAudioRecorderFactory implements AudioRecorderFactory {
  const MicrophoneAudioRecorderFactory.linux({
    required this.outputDirectory,
    this.ffmpegExecutable = 'ffmpeg',
    this.deviceResolver,
    this.processRunner,
    this.clock,
  });

  final Directory outputDirectory;
  final String ffmpegExecutable;
  final AlsaDeviceResolver? deviceResolver;
  final RecorderProcessRunner? processRunner;
  final Clock? clock;

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    return FfmpegAudioRecorder.linux(
      deviceName: microphone.alternativeName ?? microphone.name,
      outputDirectory: outputDirectory,
      executable: ffmpegExecutable,
      // Probe for an ALSA spec that actually captures (`default` fails on
      // raw-ALSA setups without PipeWire/Pulse routing).
      deviceResolver:
          deviceResolver ?? ((_) => resolveAlsaCaptureDevice(ffmpegExecutable)),
      processRunner: processRunner,
      clock: clock,
    );
  }
}
