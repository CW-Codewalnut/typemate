import 'dart:io';

import 'package:typemate/src/core/audio/ffmpeg_audio_recorder.dart';

Future<void> main(List<String> arguments) async {
  final deviceName = arguments.isNotEmpty
      ? arguments.first
      : 'Microphone (Brio 100)';
  final seconds = arguments.length > 1 ? int.parse(arguments[1]) : 3;
  final outputDirectory = Directory('build/recordings');

  final recorder = FfmpegAudioRecorder.windows(
    deviceName: deviceName,
    outputDirectory: outputDirectory,
  );

  await recorder.start();
  await Future<void>.delayed(Duration(seconds: seconds));
  final recording = await recorder.stop();

  final file = File(recording.path);
  if (!file.existsSync()) {
    stderr.writeln('Recording file was not created: ${recording.path}');
    exitCode = 1;
    return;
  }

  stdout.writeln('recording=${file.absolute.path}');
  stdout.writeln('duration=${recording.duration.inMilliseconds}ms');
  stdout.writeln('bytes=${file.lengthSync()}');
}
