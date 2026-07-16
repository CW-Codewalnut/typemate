import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/stt/language_routing_stt_engine.dart';
import 'package:typemate/src/core/stt/parakeet_server_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes English to the Parakeet server and the rest to whisper', () {
    final engine = createDefaultSttEngine(
      environment: const {},
      pathExists: (_) => true,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(engine, isA<LanguageRoutingSttEngine>());
    final routing = engine as LanguageRoutingSttEngine;

    // Every Parakeet language shares the same resident server engine.
    expect(routing.routes.keys, containsAll(parakeetLanguageCodes));
    expect(routing.routes.values.toSet(), hasLength(1));
    expect(routing.routes.containsKey('hi'), isFalse);
    expect(routing.routes.containsKey('hinglish'), isFalse);

    final parakeet = routing.routes['en'] as ParakeetServerSttEngine;
    expect(
      parakeet.serverExecutable,
      'C:/apps/typemate/bin/sherpa/sherpa-onnx-offline-websocket-server.exe',
    );
    expect(
      parakeet.encoderPath,
      'C:/apps/typemate/models/parakeet-tdt-0.6b-v3-int8/encoder.int8.onnx',
    );
    expect(
      parakeet.decoderPath,
      'C:/apps/typemate/models/parakeet-tdt-0.6b-v3-int8/decoder.int8.onnx',
    );
    expect(
      parakeet.joinerPath,
      'C:/apps/typemate/models/parakeet-tdt-0.6b-v3-int8/joiner.int8.onnx',
    );
    expect(
      parakeet.tokensPath,
      'C:/apps/typemate/models/parakeet-tdt-0.6b-v3-int8/tokens.txt',
    );

    final whisper = routing.fallback as WhisperCliSttEngine;
    expect(whisper.executable, 'C:/apps/typemate/bin/whisper/whisper-cli.exe');
    expect(
      whisper.modelPath,
      'C:/apps/typemate/models/ggml-small-vaani-hindi-q6.bin',
    );
    expect(whisper.modelPathOverridesByLanguage, {
      'hinglish': 'C:/apps/typemate/models/ggml-hindi2hinglish-swift.bin',
    });
    expect(
      whisper.vadModelPath,
      'C:/apps/typemate/models/ggml-silero-v5.1.2.bin',
    );
  });

  test('falls back to executable directory paths', () {
    const executableDirectory = 'C:/apps/typemate/build/runner';
    final engine = createDefaultSttEngine(
      environment: const {},
      pathExists: (path) => path.startsWith(executableDirectory),
      currentDirectoryPath: 'C:/somewhere/else',
      executableDirectoryPath: executableDirectory,
    );

    final routing = engine as LanguageRoutingSttEngine;
    final parakeet = routing.routes['en'] as ParakeetServerSttEngine;
    expect(
      parakeet.encoderPath,
      '$executableDirectory/models/parakeet-tdt-0.6b-v3-int8/encoder.int8.onnx',
    );
    final whisper = routing.fallback as WhisperCliSttEngine;
    expect(
      whisper.modelPath,
      '$executableDirectory/models/ggml-small-vaani-hindi-q6.bin',
    );
  });

  test('throws a clear error when the sherpa server binary is missing', () {
    expect(
      () => createDefaultSttEngine(
        environment: const {},
        pathExists: (path) => !path.contains('sherpa'),
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('sherpa-onnx-offline-websocket-server.exe'),
        ),
      ),
    );
  });

  test('throws a clear error when a Parakeet model file is missing', () {
    expect(
      () => createDefaultSttEngine(
        environment: const {},
        pathExists: (path) => !path.contains('encoder.int8.onnx'),
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('encoder.int8.onnx'),
        ),
      ),
    );
  });

  test('environment model override routes every language to whisper', () {
    final engine = createDefaultSttEngine(
      environment: const {
        'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        'TYPEMATE_WHISPER_MODEL': 'R:/Models/whisper/ggml-large-v3.bin',
      },
      pathExists: (_) => true,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(
      engine,
      isA<WhisperCliSttEngine>(),
      reason: 'an explicit model override bypasses the Parakeet server',
    );
    final whisper = engine as WhisperCliSttEngine;
    expect(whisper.executable, 'R:/Tools/whisper/whisper-cli.exe');
    expect(whisper.modelPath, 'R:/Models/whisper/ggml-large-v3.bin');
    expect(whisper.modelPathOverridesByLanguage, isEmpty);
  });
}
