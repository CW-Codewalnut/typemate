import 'dart:io';

import 'audio_recorder.dart';
import 'ffmpeg_audio_recorder.dart';
import 'microphone_discovery.dart';

export 'ffmpeg_audio_recorder.dart' show RecorderProcess, RecorderProcessRunner;

abstract interface class AudioRecorderFactory {
  AudioRecorder create(MicrophoneDevice microphone);
}

/// Builds ffmpeg-based recorders for Linux (PulseAudio); Windows and macOS
/// record through the record plugin instead.
class MicrophoneAudioRecorderFactory implements AudioRecorderFactory {
  const MicrophoneAudioRecorderFactory.linux({
    required this.outputDirectory,
    this.ffmpegExecutable = 'ffmpeg',
    this.processRunner,
    this.clock,
  });

  final Directory outputDirectory;
  final String ffmpegExecutable;
  final RecorderProcessRunner? processRunner;
  final Clock? clock;

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    // Pulse wants the source name; the display name is only a label.
    return FfmpegAudioRecorder.linux(
      deviceName: microphone.alternativeName ?? microphone.name,
      outputDirectory: outputDirectory,
      executable: ffmpegExecutable,
      processRunner: processRunner,
      clock: clock,
    );
  }
}
