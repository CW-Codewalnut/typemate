import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttProcessResult, SttProcessRunner;

class FakeDenoiserProcessRunner implements SttProcessRunner {
  FakeDenoiserProcessRunner({
    this.exitCode = 0,
    this.writesOutput = true,
    this.outputContent = 'denoised-audio',
  });

  final int exitCode;
  final bool writesOutput;
  final String outputContent;

  String? executable;
  List<String>? arguments;
  int runCount = 0;

  @override
  Future<SttProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = arguments;
    runCount += 1;
    if (writesOutput) {
      final outputArgument = arguments.singleWhere(
        (argument) => argument.startsWith('--output-wav='),
      );
      File(
        outputArgument.substring('--output-wav='.length),
      ).writeAsStringSync(outputContent);
    }
    return SttProcessResult(exitCode: exitCode, output: '');
  }
}

class ThrowingDenoiserProcessRunner implements SttProcessRunner {
  @override
  Future<SttProcessResult> run(String executable, List<String> arguments) {
    throw const ProcessException('sherpa-onnx-offline-denoiser', []);
  }
}

void main() {
  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('typemate-denoise');
  });

  tearDown(() {
    tempDirectory.deleteSync(recursive: true);
  });

  File writeRecordingFile() =>
      File('${tempDirectory.path}/clip.wav')..writeAsStringSync('raw-audio');

  AudioRecording recordingFor(File file) =>
      AudioRecording(path: file.path, duration: const Duration(seconds: 3));

  test(
    'runs the sherpa denoiser with the gtcrn model on the recording',
    () async {
      final file = writeRecordingFile();
      final runner = FakeDenoiserProcessRunner();
      final denoiser = SherpaGtcrnAudioDenoiser(
        executable: 'bin/sherpa/sherpa-onnx-offline-denoiser.exe',
        modelPath: 'models/gtcrn_simple.onnx',
        processRunner: runner,
      );

      await denoiser.denoise(recordingFor(file));

      expect(runner.executable, 'bin/sherpa/sherpa-onnx-offline-denoiser.exe');
      expect(runner.arguments, [
        '--speech-denoiser-gtcrn-model=models/gtcrn_simple.onnx',
        '--input-wav=${file.path}',
        '--output-wav=${file.path}.denoised.wav',
      ]);
    },
  );

  test('replaces the recording in place and keeps the same path', () async {
    final file = writeRecordingFile();
    final denoiser = SherpaGtcrnAudioDenoiser(
      executable: 'denoiser',
      modelPath: 'model',
      processRunner: FakeDenoiserProcessRunner(),
    );

    final result = await denoiser.denoise(recordingFor(file));

    expect(result.path, file.path);
    expect(result.duration, const Duration(seconds: 3));
    expect(file.readAsStringSync(), 'denoised-audio');
    expect(File('${file.path}.denoised.wav').existsSync(), isFalse);
  });

  test('keeps the raw recording when the denoiser exits non-zero', () async {
    final file = writeRecordingFile();
    final denoiser = SherpaGtcrnAudioDenoiser(
      executable: 'denoiser',
      modelPath: 'model',
      processRunner: FakeDenoiserProcessRunner(exitCode: 1),
    );

    final result = await denoiser.denoise(recordingFor(file));

    expect(result.path, file.path);
    expect(file.readAsStringSync(), 'raw-audio');
    expect(File('${file.path}.denoised.wav').existsSync(), isFalse);
  });

  test('keeps the raw recording when the denoiser writes no output', () async {
    final file = writeRecordingFile();
    final denoiser = SherpaGtcrnAudioDenoiser(
      executable: 'denoiser',
      modelPath: 'model',
      processRunner: FakeDenoiserProcessRunner(writesOutput: false),
    );

    final result = await denoiser.denoise(recordingFor(file));

    expect(result.path, file.path);
    expect(file.readAsStringSync(), 'raw-audio');
  });

  test(
    'keeps the raw recording when the denoiser process cannot start',
    () async {
      final file = writeRecordingFile();
      final denoiser = SherpaGtcrnAudioDenoiser(
        executable: 'denoiser',
        modelPath: 'model',
        processRunner: ThrowingDenoiserProcessRunner(),
      );

      final result = await denoiser.denoise(recordingFor(file));

      expect(result.path, file.path);
      expect(file.readAsStringSync(), 'raw-audio');
    },
  );

  test('skips empty recordings without running the process', () async {
    final runner = FakeDenoiserProcessRunner();
    final denoiser = SherpaGtcrnAudioDenoiser(
      executable: 'denoiser',
      modelPath: 'model',
      processRunner: runner,
    );

    final result = await denoiser.denoise(
      const AudioRecording(path: '', duration: Duration.zero),
    );

    expect(result.path, '');
    expect(runner.runCount, 0);
  });
}
