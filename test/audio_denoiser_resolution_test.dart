import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';

void main() {
  test('resolves the bundled GTCRN model from the current directory', () {
    final denoiser =
        createDefaultAudioDenoiser(
              environment: const {},
              pathExists: (_) => true,
              currentDirectoryPath: 'C:/apps/typemate',
              executableDirectoryPath: 'C:/apps/typemate/build/runner',
            )
            as SherpaGtcrnAudioDenoiser?;

    expect(denoiser, isNotNull);
    expect(denoiser!.modelPath, 'C:/apps/typemate/models/gtcrn_simple.onnx');
  });

  test('falls back to the executable directory', () {
    const executableDirectory = 'C:/apps/typemate/build/runner';
    final denoiser =
        createDefaultAudioDenoiser(
              environment: const {},
              pathExists: (path) => path.startsWith(executableDirectory),
              currentDirectoryPath: 'C:/somewhere/else',
              executableDirectoryPath: executableDirectory,
            )
            as SherpaGtcrnAudioDenoiser?;

    expect(denoiser, isNotNull);
    expect(
      denoiser!.modelPath,
      '$executableDirectory/models/gtcrn_simple.onnx',
    );
  });

  test('environment override wins over the bundled model path', () {
    final denoiser =
        createDefaultAudioDenoiser(
              environment: const {
                'TYPEMATE_DENOISER_MODEL': 'D:/models/gtcrn.onnx',
              },
              pathExists: (_) => false,
              currentDirectoryPath: 'C:/apps/typemate',
              executableDirectoryPath: 'C:/apps/typemate/build/runner',
            )
            as SherpaGtcrnAudioDenoiser?;

    expect(denoiser, isNotNull);
    expect(denoiser!.modelPath, 'D:/models/gtcrn.onnx');
  });

  test('returns null instead of throwing when the model is missing', () {
    final denoiser = createDefaultAudioDenoiser(
      environment: const {},
      pathExists: (_) => false,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(denoiser, isNull);
  });
}
