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
        'C:/apps/typemate/models/ggml-large-v3-turbo-q5_0.bin',
      );
      expect(whisper.modelPathOverridesByLanguage, {
        'en': 'C:/apps/typemate/models/ggml-small.bin',
      });
      expect(whisper.languageCodeProvider(), 'auto');
    },
  );

  test(
    'falls back to executable directory when working directory has no runtime',
    () {
      const executableCliPath =
          'C:/apps/typemate/build/runner/bin/whisper/whisper-cli.exe';
      const executableModelPath =
          'C:/apps/typemate/build/runner/models/ggml-large-v3-turbo-q5_0.bin';
      const executableEnglishModelPath =
          'C:/apps/typemate/build/runner/models/ggml-small.bin';
      final engine = createDefaultSttEngine(
        environment: const {},
        pathExists: (path) =>
            path == executableCliPath ||
            path == executableModelPath ||
            path == executableEnglishModelPath,
        currentDirectoryPath: 'C:/somewhere/else',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      );

      final whisper = engine as WhisperCliSttEngine;
      expect(whisper.executable, executableCliPath);
      expect(whisper.modelPath, executableModelPath);
      expect(whisper.modelPathOverridesByLanguage, {
        'en': executableEnglishModelPath,
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
          contains('models/ggml-large-v3-turbo-q5_0.bin'),
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
      'C:/apps/typemate/models/ggml-large-v3-turbo-q5_0.bin',
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
