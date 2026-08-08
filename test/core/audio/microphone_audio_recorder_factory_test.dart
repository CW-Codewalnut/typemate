import 'dart:io';

import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/audio/microphone_audio_recorder_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a Linux alsa ffmpeg recorder from selected mic', () async {
    final process = FakeRecorderProcess();
    final runner = FakeRecorderProcessRunner(process);
    final factory = MicrophoneAudioRecorderFactory.linux(
      outputDirectory: Directory('build/test-recordings'),
      processRunner: runner,
      // Pass the requested device through unchanged so the test asserts on
      // it directly instead of a live capture probe.
      deviceResolver: (requested) async => requested,
      clock: () => DateTime(2026, 7, 10, 18, 15),
    );

    final recorder = factory.create(
      const MicrophoneDevice(
        name: 'Brio 100 Mono',
        alternativeName: 'alsa_input.usb-Brio_100',
      ),
    );

    await recorder.start();
    await recorder.stop();

    expect(runner.executable, 'ffmpeg');
    expect(
      runner.arguments,
      containsAllInOrder([
        '-f',
        'alsa',
        '-i',
        'alsa_input.usb-Brio_100',
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
