import 'dart:io';

import 'package:typemate/src/core/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/core/audio/microphone_audio_recorder_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a Windows ffmpeg recorder from selected microphone', () async {
    final process = FakeRecorderProcess();
    final runner = FakeRecorderProcessRunner(process);
    final factory = MicrophoneAudioRecorderFactory.windows(
      outputDirectory: Directory('build/test-recordings'),
      processRunner: runner,
      clock: () => DateTime(2026, 7, 10, 18, 15),
    );

    final recorder = factory.create(
      const MicrophoneDevice(name: 'Microphone (Brio 100)'),
    );

    await recorder.start();
    await recorder.stop();

    expect(runner.executable, 'ffmpeg');
    expect(
      runner.arguments,
      containsAllInOrder([
        '-f',
        'dshow',
        '-i',
        'audio=Microphone (Brio 100)',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-sample_fmt',
        's16',
      ]),
    );
  });
}

class FakeRecorderProcessRunner implements RecorderProcessRunner {
  FakeRecorderProcessRunner(this.process);

  final FakeRecorderProcess process;
  String? executable;
  List<String>? arguments;

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
  @override
  Future<int> get exitCode async => 0;

  @override
  void requestStop() {}
}
