import 'dart:io';

import 'audio_recorder.dart';
import 'ffmpeg_audio_recorder.dart';
import 'ffmpeg_microphone_discovery.dart';

export 'ffmpeg_audio_recorder.dart' show RecorderProcess, RecorderProcessRunner;

abstract interface class AudioRecorderFactory {
  AudioRecorder create(MicrophoneDevice microphone);
}

class MicrophoneAudioRecorderFactory implements AudioRecorderFactory {
  MicrophoneAudioRecorderFactory.windows({
    required Directory outputDirectory,
    String ffmpegExecutable = 'ffmpeg',
    RecorderProcessRunner? processRunner,
    Clock? clock,
  }) : this._(
         isWindows: true,
         outputDirectory: outputDirectory,
         ffmpegExecutable: ffmpegExecutable,
         processRunner: processRunner,
         clock: clock,
       );

  MicrophoneAudioRecorderFactory.linux({
    required Directory outputDirectory,
    String ffmpegExecutable = 'ffmpeg',
    RecorderProcessRunner? processRunner,
    Clock? clock,
  }) : this._(
         isWindows: false,
         outputDirectory: outputDirectory,
         ffmpegExecutable: ffmpegExecutable,
         processRunner: processRunner,
         clock: clock,
       );

  const MicrophoneAudioRecorderFactory._({
    required this.isWindows,
    required this.outputDirectory,
    required this.ffmpegExecutable,
    this.processRunner,
    this.clock,
  });

  final bool isWindows;
  final Directory outputDirectory;
  final String ffmpegExecutable;
  final RecorderProcessRunner? processRunner;
  final Clock? clock;

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    if (isWindows) {
      return FfmpegAudioRecorder.windows(
        deviceName: microphone.name,
        outputDirectory: outputDirectory,
        executable: ffmpegExecutable,
        processRunner: processRunner,
        clock: clock,
      );
    }
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
