import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';

void main() {
  // The bundled binary name depends on the host OS the suite runs on
  // (.exe suffix on Windows, none on Linux), matching production behavior.
  final denoiserBinary = bundledDenoiserRelativePath.split('/').last;

  test(
    'resolves the bundled denoiser and model from the current directory',
    () {
      final denoiser =
          createDefaultAudioDenoiser(
                environment: const {},
                pathExists: (_) => true,
                currentDirectoryPath: 'C:/apps/typemate',
                executableDirectoryPath: 'C:/apps/typemate/build/runner',
              )
              as SherpaGtcrnAudioDenoiser?;

      expect(denoiser, isNotNull);
      expect(
        denoiser!.executable,
        'C:/apps/typemate/bin/sherpa/$denoiserBinary',
      );
      expect(denoiser.modelPath, 'C:/apps/typemate/models/gtcrn_simple.onnx');
    },
  );

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
      denoiser!.executable,
      '$executableDirectory/bin/sherpa/$denoiserBinary',
    );
    expect(denoiser.modelPath, '$executableDirectory/models/gtcrn_simple.onnx');
  });

  test('environment overrides win over bundled paths', () {
    final denoiser =
        createDefaultAudioDenoiser(
              environment: const {
                'TYPEMATE_DENOISER': 'D:/tools/denoiser.exe',
                'TYPEMATE_DENOISER_MODEL': 'D:/models/gtcrn.onnx',
              },
              pathExists: (_) => false,
              currentDirectoryPath: 'C:/apps/typemate',
              executableDirectoryPath: 'C:/apps/typemate/build/runner',
            )
            as SherpaGtcrnAudioDenoiser?;

    expect(denoiser, isNotNull);
    expect(denoiser!.executable, 'D:/tools/denoiser.exe');
    expect(denoiser.modelPath, 'D:/models/gtcrn.onnx');
  });

  test('returns null instead of throwing when the runtime is missing', () {
    final denoiser = createDefaultAudioDenoiser(
      environment: const {},
      pathExists: (_) => false,
      currentDirectoryPath: 'C:/apps/typemate',
      executableDirectoryPath: 'C:/apps/typemate/build/runner',
    );

    expect(denoiser, isNull);
  });
}
