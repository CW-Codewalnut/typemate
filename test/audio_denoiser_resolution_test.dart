import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';

void main() {
  const dataDirectory = 'C:/users/me/AppData/Roaming/TypeMate';

  SherpaGtcrnAudioDenoiser denoiserFor({
    required bool Function(String path) pathExists,
    Map<String, String> environment = const {},
  }) {
    final runtime = createDesktopSpeechRuntime(
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

    expect(denoiser.modelPath, 'C:/apps/typemate/models/gtcrn_simple.onnx');
  });

  test('unbundled GTCRN rides the Parakeet download (Android)', () {
    final denoiser = denoiserFor(pathExists: (_) => false);

    expect(
      denoiser.modelPath,
      '$dataDirectory/models/parakeet-tdt-0.6b-v3-int8/gtcrn_simple.onnx',
    );

    // And the Parakeet download carries the denoiser model with it.
    final runtime = createDesktopSpeechRuntime(
      dataDirectoryPath: dataDirectory,
      environment: const {},
      pathExists: (_) => false,
      languageCodeProvider: () => 'en',
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );
    expect(
      runtime.provisioner!.active!.files.map((f) => f.relativePath),
      contains('gtcrn_simple.onnx'),
    );
  });

  test('environment override wins over the bundled model path', () {
    final denoiser = denoiserFor(
      pathExists: (_) => false,
      environment: const {'TYPEMATE_DENOISER_MODEL': 'D:/models/gtcrn.onnx'},
    );

    expect(denoiser.modelPath, 'D:/models/gtcrn.onnx');
  });
}
