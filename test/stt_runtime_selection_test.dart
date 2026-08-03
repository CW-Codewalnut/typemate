import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/stt/language_routing_stt_engine.dart';
import 'package:typemate/src/core/stt/sherpa_parakeet_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_server_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The bundled binary names depend on the host OS the suite runs on
  // (.exe suffix on Windows, none on Linux), matching production behavior.
  final whisperServerBinary = bundledWhisperServerRelativePath.split('/').last;
  const dataDirectory = 'C:/users/me/AppData/Roaming/TypeMate';

  test('bundled install routes every language with nothing to download', () {
    final runtime = createDesktopSpeechRuntime(
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

    // Every whisper-server language gets its own engine on its own port.
    final seenPorts = <int>{};
    for (final language in whisperServerLanguages) {
      final server = routing.routes[language.code] as WhisperServerSttEngine;
      expect(
        server.serverExecutable,
        'C:/apps/typemate/bin/whisper/$whisperServerBinary',
      );
      expect(
        server.modelPath,
        'C:/apps/typemate/${language.modelRelativePath}',
      );
      expect(server.port, language.port);
      expect(
        seenPorts.add(server.port),
        isTrue,
        reason: 'ports must be unique per language server',
      );
      expect(
        server.vadModelPath,
        'C:/apps/typemate/models/ggml-silero-v5.1.2.bin',
      );
    }

    // Hindi is also the fallback, with the Devanagari prompt; Hinglish
    // decodes as Hindi without a prompt.
    final hindi = routing.routes['hi'] as WhisperServerSttEngine;
    expect(identical(routing.fallback, hindi), isTrue);
    expect(hindi.cliLanguage, 'hi');
    expect(hindi.prompt, contains('देवनागरी'));
    final hinglish = routing.routes['hinglish'] as WhisperServerSttEngine;
    expect(hinglish.cliLanguage, 'hi');
    expect(hinglish.prompt, isNull);

    // Tamil decodes under its own whisper code.
    final tamil = routing.routes['ta'] as WhisperServerSttEngine;
    expect(tamil.cliLanguage, 'ta');
    expect(tamil.prompt, isNull);
  });

  test('falls back to executable directory paths', () {
    const executableDirectory = 'C:/apps/typemate/build/runner';
    final runtime = createDesktopSpeechRuntime(
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
    final hindi = routing.fallback as WhisperServerSttEngine;
    expect(
      hindi.modelPath,
      '$executableDirectory/models/ggml-small-vaani-hindi-q6.bin',
    );
  });

  test('slim install downloads models on demand per language', () {
    // Binaries and the small VAD model are bundled; every large model is
    // not (the slim installer case).
    bool bundled(String path) =>
        path.contains('/bin/') || path.contains('ggml-silero');
    var languageCode = 'en';
    final runtime = createDesktopSpeechRuntime(
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
    final hindi = routing.routes['hi'] as WhisperServerSttEngine;
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
    expect(
      provisioner.expectedTotalBytes,
      parakeetModelFiles.fold<int>(0, (sum, f) => sum + f.expectedBytes),
    );

    // Every Parakeet language shares one download; whisper languages get
    // their own model file each.
    final english = provisioner.active;
    languageCode = 'de';
    expect(identical(provisioner.active, english), isTrue);
    languageCode = 'hi';
    expect(identical(provisioner.active, english), isFalse);
    expect(
      provisioner.active!.files.single.relativePath,
      'ggml-small-vaani-hindi-q6.bin',
    );
    languageCode = 'ta';
    expect(
      provisioner.active!.files.single.relativePath,
      'ggml-vistaar-tamil-small-q5_0.bin',
    );
  });

  test('a bundled language downloads nothing even on a slim install', () {
    // Hindi's model is bundled; Parakeet and the other whisper models are
    // not — only the missing ones may download.
    bool bundled(String path) =>
        path.contains('/bin/') ||
        path.contains('ggml-silero') ||
        path.contains('ggml-small-vaani-hindi-q6.bin');
    var languageCode = 'hi';
    final runtime = createDesktopSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: bundled,
      languageCodeProvider: () => languageCode,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    final routing = runtime.engine as LanguageRoutingSttEngine;
    final hindi = routing.routes['hi'] as WhisperServerSttEngine;
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

  test('an incomplete bundled Parakeet directory downloads instead', () {
    // A bundled copy missing one file must not be trusted: the engine
    // points at the data directory and the download provides all files.
    bool bundled(String path) =>
        !path.contains('encoder.int8.onnx') || path.contains(dataDirectory);
    final runtime = createDesktopSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: bundled,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    final routing = runtime.engine as LanguageRoutingSttEngine;
    final parakeet = routing.routes['en'] as SherpaParakeetSttEngine;
    expect(
      parakeet.modelDirectoryPath,
      '$dataDirectory/models/parakeet-tdt-0.6b-v3-int8',
    );
    expect(runtime.provisioner!.active, isNotNull);
  });

  test('throws a clear error when the whisper server binary is missing', () {
    expect(
      () => createDesktopSpeechRuntime(
        dataDirectoryPath: dataDirectory,
        environment: const {},
        pathExists: (path) => !path.contains(whisperServerBinary),
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains(whisperServerBinary),
        ),
      ),
    );
  });

  test('throws a clear error when the VAD model is missing', () {
    expect(
      () => createDesktopSpeechRuntime(
        dataDirectoryPath: dataDirectory,
        environment: const {},
        pathExists: (path) => !path.contains('ggml-silero'),
        currentDirectoryPath: 'C:/apps/typemate',
        executableDirectoryPath: 'C:/apps/typemate/build/runner',
      ),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('ggml-silero'),
        ),
      ),
    );
  });

  test('environment model override routes every language to whisper CLI', () {
    final runtime = createDesktopSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {
        'TYPEMATE_WHISPER_CLI': 'R:/Tools/whisper/whisper-cli.exe',
        'TYPEMATE_WHISPER_MODEL': 'R:/Models/whisper/ggml-large-v3.bin',
      },
      pathExists: (_) => true,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(
      runtime.engine,
      isA<WhisperCliSttEngine>(),
      reason: 'an explicit model override bypasses the resident engines',
    );
    expect(runtime.provisioner, isNull);
    final whisper = runtime.engine as WhisperCliSttEngine;
    expect(whisper.executable, 'R:/Tools/whisper/whisper-cli.exe');
    expect(whisper.modelPath, 'R:/Models/whisper/ggml-large-v3.bin');
    expect(whisper.modelPathOverridesByLanguage, isEmpty);
  });
}
