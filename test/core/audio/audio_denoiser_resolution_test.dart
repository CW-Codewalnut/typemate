import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';

void main() {
  const dataDirectory = 'C:/users/me/AppData/Roaming/TypeMate';

  SherpaGtcrnAudioDenoiser denoiserFor({
    required bool Function(String path) pathExists,
    Map<String, String> environment = const {},
  }) {
    final runtime = createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: environment,
      pathExists: pathExists,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );
    return runtime.denoiser as SherpaGtcrnAudioDenoiser;
  }

  test('resolves the bundled GTCRN model from the current directory', () {
    final denoiser = denoiserFor(pathExists: (_) => true);

    expect(denoiser.modelPathCandidates, [
      'C:/apps/typemate/models/gtcrn_simple.onnx',
    ]);
  });

  test('unbundled GTCRN rides either Parakeet download (Android)', () {
    // GTCRN lands inside whichever Parakeet directory downloads first —
    // English's unified or the multilingual v3 — so the denoiser checks both.
    final denoiser = denoiserFor(pathExists: (_) => false);

    expect(denoiser.modelPathCandidates, [
      '$dataDirectory/models/parakeet-unified-en-0.6b-int8/gtcrn_simple.onnx',
      '$dataDirectory/models/parakeet-tdt-0.6b-v3-int8/gtcrn_simple.onnx',
    ]);

    // And both Parakeet downloads carry the denoiser model with them.
    SpeechRuntime runtimeFor(String code) => createSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: (_) => false,
      languageCodeProvider: () => code,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );
    for (final code in const ['en', 'de']) {
      expect(
        runtimeFor(code).provisioner!.active!.files.map((f) => f.relativePath),
        contains('gtcrn_simple.onnx'),
      );
    }
  });

  test('environment override wins over the bundled model path', () {
    final denoiser = denoiserFor(
      pathExists: (_) => false,
      environment: const {'TYPEMATE_DENOISER_MODEL': 'D:/models/gtcrn.onnx'},
    );

    expect(denoiser.modelPathCandidates, ['D:/models/gtcrn.onnx']);
  });
}
