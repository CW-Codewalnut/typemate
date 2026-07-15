import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uses the bundled CLI and turbo model when environment is not configured',
    () {
      final engine = createDefaultSttEngine(
        environment: const {},
        pathExists: (_) => true,
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      );

      expect(engine, isA<WhisperCliSttEngine>());
      final whisper = engine as WhisperCliSttEngine;
      expect(
        whisper.executable,
        'C:/apps/typemate/bin/whisper/whisper-cli.exe',
      );
      expect(
        whisper.modelPath,
        'C:/apps/typemate/models/ggml-distil-small.en.bin',
      );
      expect(whisper.modelPathOverridesByLanguage, {
        'hi': 'C:/apps/typemate/models/ggml-small-vaani-hindi-q6.bin',
        'hinglish': 'C:/apps/typemate/models/ggml-hindi2hinglish-apex-q5_1.bin',
      });
      expect(
        whisper.vadModelPath,
        'C:/apps/typemate/models/ggml-silero-v5.1.2.bin',
      );
      expect(whisper.languageCodeProvider(), 'auto');
    },
  );

  test(
    'falls back to executable directory when working directory has no runtime',
    () {
      const executableDirectory = 'C:/apps/typemate/build/runner';
      const executableCliPath =
          '$executableDirectory/bin/whisper/whisper-cli.exe';
      const executableModelPath =
          '$executableDirectory/models/ggml-distil-small.en.bin';
      const executableHindiModelPath =
          '$executableDirectory/models/ggml-small-vaani-hindi-q6.bin';
      const executableHinglishModelPath =
          '$executableDirectory/models/ggml-hindi2hinglish-apex-q5_1.bin';
      final engine = createDefaultSttEngine(
        environment: const {},
        pathExists: (path) => path.startsWith(executableDirectory),
        currentDirectoryPath: 'C:/somewhere/else',
        executableDirectoryPath: executableDirectory,
      );

      final whisper = engine as WhisperCliSttEngine;
      expect(whisper.executable, executableCliPath);
      expect(whisper.modelPath, executableModelPath);
      expect(whisper.modelPathOverridesByLanguage, {
        'hi': executableHindiModelPath,
        'hinglish': executableHinglishModelPath,
      });
    },
  );

  test('throws a clear error when the bundled whisper CLI is missing', () {
    expect(
      () => createDefaultSttEngine(
        environment: const {},
        pathExists: (_) => false,
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('bin/whisper/whisper-cli.exe'),
        ),
      ),
    );
  });

  test('throws a clear error when the bundled model is missing', () {
    expect(
      () => createDefaultSttEngine(
        environment: const {},
        pathExists: (path) => path.endsWith('whisper-cli.exe'),
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('models/ggml-distil-small.en.bin'),
        ),
      ),
    );
  });

  test('environment overrides win over the bundled runtime', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        'TYPEMATE_WHISPER_MODEL': 'R:/Models/whisper/ggml-large-v3.bin',
      },
      pathExists: (_) => true,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'R:/Tools/whisper/whisper-cli.exe');
    expect(whisper.modelPath, 'R:/Models/whisper/ggml-large-v3.bin');
    expect(
      whisper.modelPathOverridesByLanguage,
      isEmpty,
      reason: 'an explicit model override applies to every language',
    );
  });

  test('mixes an environment CLI override with the bundled model', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
      },
      pathExists: (path) => path.endsWith('.bin'),
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'R:/Tools/whisper/whisper-cli.exe');
    expect(
      whisper.modelPath,
      'C:/apps/typemate/models/ggml-distil-small.en.bin',
    );
  });

  test('trims whisper environment values before creating the runtime', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': '  whisper-cli  ',
        'TYPEMATE_WHISPER_MODEL': '  models/tiny.bin  ',
      },
      pathExists: (_) => true,
    );

    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'whisper-cli');
    expect(whisper.modelPath, 'models/tiny.bin');
  });
}
