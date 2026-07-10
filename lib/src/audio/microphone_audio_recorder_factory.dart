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
    RecorderProcessRunner? processRunner,
    Clock? clock,
  }) : this._(
         outputDirectory: outputDirectory,
         processRunner: processRunner,
         clock: clock,
       );

  const MicrophoneAudioRecorderFactory._({
    required this.outputDirectory,
    this.processRunner,
    this.clock,
  });

  final Directory outputDirectory;
  final RecorderProcessRunner? processRunner;
  final Clock? clock;

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    return FfmpegAudioRecorder.windows(
      deviceName: microphone.name,
      outputDirectory: outputDirectory,
      processRunner: processRunner,
      clock: clock,
    );
  }
}
