import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uses verified local Whisper paths when environment is not configured',
    () {
      final engine = createDefaultSttEngine(
        environment: const {},
        pathExists: (_) => true,
      );

      expect(engine, isA<WhisperCliSttEngine>());
      final whisper = engine as WhisperCliSttEngine;
      expect(
        whisper.executable,
        'R:/Tools/whisper.cpp/v1.9.1-x64/Release/whisper-cli.exe',
      );
      expect(whisper.modelPath, 'R:/Models/whisper/ggml-base.bin');
      expect(whisper.languageCodeProvider(), 'auto');
    },
  );

  test('falls back to mock STT when no configured or verified paths exist', () {
    final engine = createDefaultSttEngine(
      environment: const {},
      pathExists: (_) => false,
    );

    expect(engine, isA<MockSttEngine>());
  });

  test(
    'uses mock STT when only one whisper environment value is configured',
    () {
      final engine = createDefaultSttEngine(
        environment: const {
          'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        },
        pathExists: (_) => false,
      );

      expect(engine, isA<MockSttEngine>());
    },
  );

  test('uses whisper CLI STT when runtime and model are configured', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        'TYPEMATE_WHISPER_MODEL': 'R:/Models/ggml-base.bin',
      },
    );

    expect(engine, isA<WhisperCliSttEngine>());
    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'R:/Tools/whisper/whisper-cli.exe');
    expect(whisper.modelPath, 'R:/Models/ggml-base.bin');
  });

  test('trims whisper environment values before creating the runtime', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': '  whisper-cli  ',
        'TYPEMATE_WHISPER_MODEL': '  models/tiny.bin  ',
      },
    );

    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'whisper-cli');
    expect(whisper.modelPath, 'models/tiny.bin');
  });
}
