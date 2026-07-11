import 'package:dictation_flow/src/audio/audio_recorder.dart';
import 'package:dictation_flow/src/stt/whisper_cli_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'isReady returns true when the executable can report its version',
    () async {
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(exitCode: 0, output: 'whisper.cpp 1.7'),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-tiny.en.bin',
        processRunner: runner,
      );

      expect(await engine.isReady(), isTrue);
      expect(runner.executable, 'whisper-cli');
      expect(runner.arguments, ['--version']);
    },
  );

  test('isReady returns false when the executable cannot run', () async {
    final runner = ThrowingSttProcessRunner();
    final engine = WhisperCliSttEngine(
      executable: 'missing-whisper-cli',
      modelPath: 'models/ggml-tiny.en.bin',
      processRunner: runner,
    );

    expect(await engine.isReady(), isFalse);
  });

  test(
    'prepare fails with an actionable message when runtime is unavailable',
    () async {
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(exitCode: 1, output: 'not found'),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-tiny.en.bin',
        processRunner: runner,
      );

      expect(
        engine.prepare,
        throwsA(
          isA<SttRuntimeException>().having(
            (error) => error.message,
            'message',
            'Local speech runtime is not ready. Check whisper.cpp and the model file.',
          ),
        ),
      );
    },
  );

  test('transcribe runs whisper CLI and parses stdout transcript', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(
        exitCode: 0,
        output: '[00:00:00.000 --> 00:00:01.000]  Hello TypeMate.\n',
      ),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-tiny.en.bin',
      processRunner: runner,
    );

    final transcript = await engine.transcribe(
      const AudioRecording(
        path: 'build/recordings/sample.wav',
        duration: Duration(seconds: 1),
      ),
    );

    expect(transcript, 'Hello TypeMate.');
    expect(runner.executable, 'whisper-cli');
    expect(runner.arguments, [
      '-m',
      'models/ggml-tiny.en.bin',
      '-f',
      'build/recordings/sample.wav',
      '--no-timestamps',
    ]);
  });

  test('transcribe surfaces an actionable error when whisper fails', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 2, output: 'model load failed'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-tiny.en.bin',
      processRunner: runner,
    );

    expect(
      () => engine.transcribe(
        const AudioRecording(path: 'voice.wav', duration: Duration(seconds: 1)),
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          'Local transcription failed. Check the whisper.cpp runtime and model file.',
        ),
      ),
    );
  });
}

class FakeSttProcessRunner implements SttProcessRunner {
  FakeSttProcessRunner({required this.result});

  final SttProcessResult result;
  late String executable;
  late List<String> arguments;

  @override
  Future<SttProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = arguments;
    return result;
  }
}

class ThrowingSttProcessRunner implements SttProcessRunner {
  @override
  Future<SttProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    throw StateError('missing executable');
  }
}
