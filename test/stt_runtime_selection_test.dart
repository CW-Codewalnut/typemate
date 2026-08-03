import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/stt/language_routing_stt_engine.dart';
import 'package:typemate/src/core/stt/sherpa_parakeet_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_ggml_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dataDirectory = 'C:/users/me/AppData/Roaming/TypeMate';

  test('bundled install routes every language with nothing to download', () {
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: (_) => true,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(
      runtime.provisioner,
      isNull,
      reason: 'every model is bundled, so there is nothing to download',
    );
    expect(runtime.engine, isA<LanguageRoutingSttEngine>());
    final routing = runtime.engine as LanguageRoutingSttEngine;

    // Every Parakeet language shares the same in-process engine, loading
    // the bundled model directory.
    expect(routing.routes.keys, containsAll(parakeetLanguageCodes));
    final parakeet = routing.routes['en'] as SherpaParakeetSttEngine;
    expect(
      parakeet.modelDirectoryPath,
      'C:/apps/typemate/models/parakeet-tdt-0.6b-v3-int8',
    );
    expect(parakeet.numThreads, desktopParakeetNumThreads);

    // Every whisper language runs in-process on its own fine-tune, with
    // the bundled Silero VAD trimming hold-to-talk silence.
    for (final language in whisperLanguages) {
      final engine = routing.routes[language.code] as WhisperGgmlSttEngine;
      expect(
        engine.modelPath,
        'C:/apps/typemate/${language.modelRelativePath}',
      );
      expect(
        engine.vadModelPath,
        'C:/apps/typemate/models/ggml-silero-v5.1.2.bin',
      );
    }

    // Hindi is also the fallback; Hinglish decodes as Hindi (its
    // fine-tune romanizes on its own). No prompts on the in-process
    // path: the fine-tunes carry their scripts natively.
    final hindi = routing.routes['hi'] as WhisperGgmlSttEngine;
    expect(identical(routing.fallback, hindi), isTrue);
    expect(hindi.language, 'hi');
    expect(hindi.prompt, isNull);
    final hinglish = routing.routes['hinglish'] as WhisperGgmlSttEngine;
    expect(hinglish.language, 'hi');
    expect(hinglish.prompt, isNull);

    // Tamil decodes under its own whisper code.
    final tamil = routing.routes['ta'] as WhisperGgmlSttEngine;
    expect(tamil.language, 'ta');
    expect(tamil.prompt, isNull);
  });

  test('falls back to executable directory paths', () {
    const executableDirectory = 'C:/apps/typemate/build/runner';
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: (path) => path.startsWith(executableDirectory),
      currentDirectoryPath: 'C:/somewhere/else',
      executableDirectoryPath: executableDirectory,
    );

    final routing = runtime.engine as LanguageRoutingSttEngine;
    final parakeet = routing.routes['en'] as SherpaParakeetSttEngine;
    expect(
      parakeet.modelDirectoryPath,
      '$executableDirectory/models/parakeet-tdt-0.6b-v3-int8',
    );
    final hindi = routing.fallback as WhisperGgmlSttEngine;
    expect(
      hindi.modelPath,
      '$executableDirectory/models/ggml-small-vaani-hindi-q6.bin',
    );
  });

  test('slim install downloads models on demand per language', () {
    // Only the small VAD model is bundled; every large model is not (the
    // slim installer case).
    bool bundled(String path) => path.contains('ggml-silero');
    var languageCode = 'en';
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: bundled,
      languageCodeProvider: () => languageCode,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    // Engines point into the per-user data directory, where the
    // provisioner downloads to.
    final routing = runtime.engine as LanguageRoutingSttEngine;
    final parakeet = routing.routes['en'] as SherpaParakeetSttEngine;
    expect(
      parakeet.modelDirectoryPath,
      '$dataDirectory/models/parakeet-tdt-0.6b-v3-int8',
    );
    final hindi = routing.routes['hi'] as WhisperGgmlSttEngine;
    expect(
      hindi.modelPath,
      '$dataDirectory/models/ggml-small-vaani-hindi-q6.bin',
    );

    final provisioner = runtime.provisioner!;
    // English needs the four Parakeet files (~640 MB total).
    expect(provisioner.active, isNotNull);
    expect(
      provisioner.active!.files.map((f) => f.relativePath),
      containsAll(['encoder.int8.onnx', 'tokens.txt']),
    );

    // Every Parakeet language shares one download; whisper languages get
    // their own model file each.
    final english = provisioner.active;
    languageCode = 'de';
    expect(identical(provisioner.active, english), isTrue);
    languageCode = 'hi';
    expect(identical(provisioner.active, english), isFalse);
    expect(provisioner.active!.files.map((f) => f.relativePath), [
      'ggml-small-vaani-hindi-q6.bin',
    ]);
    languageCode = 'ta';
    expect(provisioner.active!.files.map((f) => f.relativePath), [
      'ggml-vistaar-tamil-small-q5_0.bin',
    ]);
  });

  test('an unbundled VAD model rides the whisper download (Android)', () {
    // Nothing bundled at all — the Android case.
    var languageCode = 'hi';
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: (_) => false,
      languageCodeProvider: () => languageCode,
      currentDirectoryPath: '/nonexistent',
      executableDirectoryPath: '/nonexistent',
    );

    final routing = runtime.engine as LanguageRoutingSttEngine;
    final hindi = routing.routes['hi'] as WhisperGgmlSttEngine;
    expect(hindi.vadModelPath, '$dataDirectory/models/ggml-silero-v5.1.2.bin');

    final provisioner = runtime.provisioner!;
    expect(
      provisioner.active!.files.map((f) => f.relativePath),
      containsAll(['ggml-small-vaani-hindi-q6.bin', 'ggml-silero-v5.1.2.bin']),
    );
  });

  test('a bundled language downloads nothing even on a slim install', () {
    // Hindi's model and the VAD are bundled; Parakeet and the other
    // whisper models are not — only the missing ones may download.
    bool bundled(String path) =>
        path.contains('ggml-silero') ||
        path.contains('ggml-small-vaani-hindi-q6.bin');
    var languageCode = 'hi';
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: bundled,
      languageCodeProvider: () => languageCode,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    final routing = runtime.engine as LanguageRoutingSttEngine;
    final hindi = routing.routes['hi'] as WhisperGgmlSttEngine;
    expect(
      hindi.modelPath,
      'C:/apps/typemate/models/ggml-small-vaani-hindi-q6.bin',
    );

    final provisioner = runtime.provisioner!;
    expect(provisioner.active, isNull);
    expect(provisioner.isReady, isTrue);
    languageCode = 'en';
    expect(provisioner.active, isNotNull);
    expect(provisioner.isReady, isFalse);
  });

  test('environment model override routes every language in-process', () {
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {
        'TYPEMATE_WHISPER_MODEL': 'R:/Models/whisper/ggml-large-v3.bin',
      },
      pathExists: (_) => true,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(runtime.provisioner, isNull);
    final routing = runtime.engine as LanguageRoutingSttEngine;
    final hindi = routing.routes['hi'] as WhisperGgmlSttEngine;
    expect(hindi.modelPath, 'R:/Models/whisper/ggml-large-v3.bin');
    expect(hindi.language, 'hi');
    final hinglish = routing.routes['hinglish'] as WhisperGgmlSttEngine;
    expect(hinglish.language, 'hi');
  });
}
