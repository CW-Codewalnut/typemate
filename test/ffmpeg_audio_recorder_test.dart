import 'dart:io';

import 'package:typemate/src/core/audio/ffmpeg_audio_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'start launches ffmpeg and stop returns the recorded wav path',
    () async {
      final process = FakeRecorderProcess();
      final runner = FakeRecorderProcessRunner(process);
      var now = DateTime(2026, 7, 10, 12, 30, 5);
      final recorder = FfmpegAudioRecorder.windows(
        deviceName: 'Microphone (Brio 100)',
        outputDirectory: Directory('build/test-recordings'),
        processRunner: runner,
        clock: () => now,
      );

      await recorder.start();
      now = now.add(const Duration(seconds: 2));
      final recording = await recorder.stop();

      expect(runner.executable, 'ffmpeg');
      expect(runner.arguments, containsAll(['-f', 'dshow']));
      expect(runner.arguments, contains('audio=Microphone (Brio 100)'));
      expect(process.quitRequested, isTrue);
      expect(recording.path, endsWith('typemate-20260710-123005.wav'));
      expect(recording.duration, greaterThan(Duration.zero));
    },
  );
}

class FakeRecorderProcessRunner implements RecorderProcessRunner {
  FakeRecorderProcessRunner(this.process);

  final FakeRecorderProcess process;
  late String executable;
  late List<String> arguments;

  @override
  Future<RecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = arguments;
    return process;
  }
}

class FakeRecorderProcess implements RecorderProcess {
  bool quitRequested = false;

  @override
  Future<int> get exitCode async => 0;

  @override
  void requestStop() {
    quitRequested = true;
  }
}
