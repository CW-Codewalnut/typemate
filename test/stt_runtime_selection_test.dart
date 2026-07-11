import 'package:typemate/src/app.dart';
import 'package:typemate/src/stt/mock_stt_engine.dart';
import 'package:typemate/src/stt/whisper_cli_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses mock STT when whisper environment is not configured', () {
    final engine = createDefaultSttEngine(environment: const {});

    expect(engine, isA<MockSttEngine>());
  });

  test(
    'uses mock STT when only one whisper environment value is configured',
    () {
      final engine = createDefaultSttEngine(
        environment: const {
          'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        },
      );

      expect(engine, isA<MockSttEngine>());
    },
  );

  test('uses whisper CLI STT when runtime and model are configured', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        'TYPEMATE_WHISPER_MODEL': 'R:/Models/ggml-tiny.en.bin',
      },
    );

    expect(engine, isA<WhisperCliSttEngine>());
    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'R:/Tools/whisper/whisper-cli.exe');
    expect(whisper.modelPath, 'R:/Models/ggml-tiny.en.bin');
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
