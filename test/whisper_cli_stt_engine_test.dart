import 'dart:convert';
import 'dart:io';

import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';
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
        modelPath: 'models/ggml-base.bin',
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
      modelPath: 'models/ggml-base.bin',
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
        modelPath: 'models/ggml-base.bin',
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
      modelPath: 'models/ggml-base.bin',
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
    expect(
      runner.arguments,
      containsAllInOrder(['-m', 'models/ggml-base.bin']),
    );
    expect(
      runner.arguments,
      containsAllInOrder(['-f', 'build/recordings/sample.wav']),
    );
    expect(runner.arguments, contains('--no-timestamps'));
    expect(runner.arguments, contains('-otxt'));
    expect(runner.arguments, contains('-of'));
    expect(runner.arguments, containsAllInOrder(['-l', 'auto']));
  });

  test(
    'transcribe uses greedy decoding to keep dictation latency low',
    () async {
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-large-v3-turbo-q5_0.bin',
        processRunner: runner,
      );

      await engine.transcribe(
        const AudioRecording(
          path: 'build/recordings/sample.wav',
          duration: Duration(seconds: 1),
        ),
      );

      expect(runner.arguments, containsAllInOrder(['--beam-size', '1']));
      expect(runner.arguments, containsAllInOrder(['--best-of', '1']));
    },
  );

  test(
    'transcribe right-sizes the encoder window to the clip length',
    () async {
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-large-v3-turbo-q5_0.bin',
        languageCodeProvider: () => 'en',
        processRunner: runner,
      );

      // 8 seconds of audio + 2s margin = 10s of the 30s window -> 500 frames.
      await engine.transcribe(
        const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 8)),
      );
      expect(runner.arguments, containsAllInOrder(['--audio-ctx', '500']));

      // Very short clips keep a minimum context.
      await engine.transcribe(
        const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 1)),
      );
      expect(runner.arguments, containsAllInOrder(['--audio-ctx', '150']));
    },
  );

  test(
    'transcribe keeps the full encoder window for auto language detection',
    () async {
      // Language detection misfires on a reduced window and produces garbage
      // transcripts, so the speedup only applies to an explicit language.
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-large-v3-turbo-q5_0.bin',
        languageCodeProvider: () => 'auto',
        processRunner: runner,
      );

      await engine.transcribe(
        const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 8)),
      );
      expect(runner.arguments, isNot(contains('--audio-ctx')));
    },
  );

  test(
    'transcribe keeps the full encoder window when duration is unknown or long',
    () async {
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-large-v3-turbo-q5_0.bin',
        languageCodeProvider: () => 'en',
        processRunner: runner,
      );

      await engine.transcribe(
        const AudioRecording(path: 'clip.wav', duration: Duration.zero),
      );
      expect(runner.arguments, isNot(contains('--audio-ctx')));

      await engine.transcribe(
        const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 40)),
      );
      expect(runner.arguments, isNot(contains('--audio-ctx')));
    },
  );

  test('transcribe picks the per-language model when one is mapped', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
    );
    final languageCodes = ['en', 'hi'];
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-large-v3-turbo-q5_0.bin',
      modelPathOverridesByLanguage: const {'en': 'models/ggml-small.bin'},
      languageCodeProvider: () => languageCodes.removeAt(0),
      processRunner: runner,
    );

    // English routes to the fast model.
    await engine.transcribe(
      const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 2)),
    );
    expect(
      runner.arguments,
      containsAllInOrder(['-m', 'models/ggml-small.bin']),
    );

    // Hindi keeps the accurate default model.
    await engine.transcribe(
      const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 2)),
    );
    expect(
      runner.arguments,
      containsAllInOrder(['-m', 'models/ggml-large-v3-turbo-q5_0.bin']),
    );
  });

  test('transcribe passes the selected language to whisper CLI', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'नमस्ते।\n'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-base.bin',
      languageCodeProvider: () => 'hi',
      processRunner: runner,
    );

    await engine.transcribe(
      const AudioRecording(path: 'hindi.wav', duration: Duration(seconds: 1)),
    );

    expect(runner.arguments, containsAllInOrder(['-l', 'hi']));
    expect(runner.arguments, contains('--prompt'));
    expect(runner.arguments.join(' '), contains('देवनागरी'));
  });

  test('transcribe does not add a script prompt for auto language', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-base.bin',
      languageCodeProvider: () => 'auto',
      processRunner: runner,
    );

    await engine.transcribe(
      const AudioRecording(path: 'english.wav', duration: Duration(seconds: 1)),
    );

    expect(runner.arguments, containsAllInOrder(['-l', 'auto']));
    expect(runner.arguments, isNot(contains('--prompt')));
  });

  test('transcribe trims silence with VAD when a model is provided', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-tiny.en.bin',
      vadModelPath: 'models/ggml-silero-v5.1.2.bin',
      languageCodeProvider: () => 'en',
      processRunner: runner,
    );

    await engine.transcribe(
      const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 2)),
    );

    expect(runner.arguments, contains('--vad'));
    expect(
      runner.arguments,
      containsAllInOrder(['--vad-model', 'models/ggml-silero-v5.1.2.bin']),
    );
    expect(
      runner.arguments,
      containsAllInOrder(['--vad-speech-pad-ms', '100']),
    );
  });

  test('transcribe skips VAD when no VAD model is provided', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'Hello.\n'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-tiny.en.bin',
      languageCodeProvider: () => 'en',
      processRunner: runner,
    );

    await engine.transcribe(
      const AudioRecording(path: 'clip.wav', duration: Duration(seconds: 2)),
    );

    expect(runner.arguments, isNot(contains('--vad')));
  });

  test('transcribe keeps English output in the selected language', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'Transcript.\n'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-tiny.en.bin',
      languageCodeProvider: () => 'en',
      processRunner: runner,
    );

    await engine.transcribe(
      const AudioRecording(path: 'en.wav', duration: Duration(seconds: 1)),
    );

    final arguments = runner.arguments.join(' ');
    expect(runner.arguments, containsAllInOrder(['-l', 'en']));
    expect(runner.arguments, contains('--prompt'));
    expect(arguments, contains('spoken English audio'));
  });

  test(
    'transcribe maps Hinglish to the hi language flag without a prompt',
    () async {
      final runner = FakeSttProcessRunner(
        result: const SttProcessResult(
          exitCode: 0,
          output: 'Aaj mausam bahut achchha hai.\n',
        ),
      );
      final engine = WhisperCliSttEngine(
        executable: 'whisper-cli',
        modelPath: 'models/ggml-tiny.en.bin',
        modelPathOverridesByLanguage: const {
          'hinglish': 'models/ggml-hindi2hinglish-swift.bin',
        },
        languageCodeProvider: () => 'hinglish',
        processRunner: runner,
      );

      final transcript = await engine.transcribe(
        const AudioRecording(
          path: 'hinglish.wav',
          duration: Duration(seconds: 2),
        ),
      );

      expect(transcript, 'Aaj mausam bahut achchha hai.');
      expect(
        runner.arguments,
        containsAllInOrder(['-m', 'models/ggml-hindi2hinglish-swift.bin']),
      );
      // whisper-cli does not know 'hinglish'; the model is task-trained to
      // romanize, so it runs as Hindi with no script prompt.
      expect(runner.arguments, containsAllInOrder(['-l', 'hi']));
      expect(runner.arguments, isNot(contains('--prompt')));
      // The clip-sized encoder window still applies.
      expect(runner.arguments, contains('--audio-ctx'));
    },
  );

  test('transcribe preserves Hindi UTF-8 transcript text', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 0, output: 'आज लिए\n'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-base.bin',
      processRunner: runner,
    );

    final transcript = await engine.transcribe(
      const AudioRecording(path: 'hindi.wav', duration: Duration(seconds: 1)),
    );

    expect(transcript, 'आज लिए');
    expect(transcript, isNot(contains('à¤')));
  });

  test('transcribe prefers UTF-8 text output file over stdout', () async {
    final runner = WritingTranscriptFileRunner(
      result: const SttProcessResult(exitCode: 0, output: '?????\n'),
      transcriptText: 'नमस्ते दुनिया\n',
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-base.bin',
      languageCodeProvider: () => 'hi',
      processRunner: runner,
    );

    final transcript = await engine.transcribe(
      const AudioRecording(path: 'hindi.wav', duration: Duration(seconds: 1)),
    );

    expect(transcript, 'नमस्ते दुनिया');
    expect(transcript, isNot(contains('?')));
    expect(runner.arguments, contains('-otxt'));
  });

  test('transcribe ignores stderr diagnostics on success', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(
        exitCode: 0,
        output: 'Clean transcript.\n',
        diagnostics:
            'whisper_model_load: loading model\nwhisper_print_timings: total time = 123 ms',
      ),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-base.bin',
      processRunner: runner,
    );

    final transcript = await engine.transcribe(
      const AudioRecording(path: 'voice.wav', duration: Duration(seconds: 1)),
    );

    expect(transcript, 'Clean transcript.');
    expect(transcript, isNot(contains('whisper_model_load')));
  });

  test('transcribe surfaces an actionable error when whisper fails', () async {
    final runner = FakeSttProcessRunner(
      result: const SttProcessResult(exitCode: 2, output: 'model load failed'),
    );
    final engine = WhisperCliSttEngine(
      executable: 'whisper-cli',
      modelPath: 'models/ggml-base.bin',
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

  group('DartSttProcessRunner', () {
    test('returns output for a process that finishes in time', () async {
      const runner = DartSttProcessRunner();
      final result = Platform.isWindows
          ? await runner.run('cmd', ['/c', 'echo hi'])
          : await runner.run('echo', ['hi']);

      expect(result.exitCode, 0);
      expect(result.output.trim(), 'hi');
    });

    test('kills a hung process and reports it took too long', () async {
      const runner = DartSttProcessRunner(timeout: Duration(milliseconds: 300));
      final hangingCommand = Platform.isWindows
          ? runner.run('ping', ['-n', '30', '127.0.0.1'])
          : runner.run('sleep', ['30']);

      await expectLater(
        hangingCommand,
        throwsA(
          isA<SttRuntimeException>().having(
            (error) => error.message,
            'message',
            contains('took too long'),
          ),
        ),
      );
    });
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

class WritingTranscriptFileRunner implements SttProcessRunner {
  WritingTranscriptFileRunner({
    required this.result,
    required this.transcriptText,
  });

  final SttProcessResult result;
  final String transcriptText;
  late List<String> arguments;

  @override
  Future<SttProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.arguments = arguments;
    final outputFileIndex = arguments.indexOf('-of');
    if (outputFileIndex >= 0 && outputFileIndex + 1 < arguments.length) {
      final outputPrefix = arguments[outputFileIndex + 1];
      final outputFile = File('$outputPrefix.txt');
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(transcriptText, encoding: utf8);
    }
    return result;
  }
}
