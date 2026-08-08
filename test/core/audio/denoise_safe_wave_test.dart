import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:typemate/src/core/audio/audio_denoiser.dart';

/// The denoiser is the path that actually closes the reported crash:
/// noise suppression runs BEFORE transcription and is on by default, so
/// GTCRN is the first native code any bad recording reaches.
///
/// `WaveData` is a plain Dart class, so these hand the denoiser the exact
/// shapes that abort natively — without the GTCRN model or any FFI.
sherpa_onnx.WaveData wave({
  required int sampleCount,
  required int sampleRate,
}) => sherpa_onnx.WaveData(
  samples: Float32List(sampleCount),
  sampleRate: sampleRate,
);

void main() {
  test('an unreadable recording never reaches GTCRN', () {
    var nativeCalls = 0;

    expect(
      () => denoiseSafeWave<int>(
        'clip.wav',
        // What readWave returns for a missing, empty or truncated file:
        // it does not throw.
        readWave: (_) => wave(sampleCount: 0, sampleRate: 0),
        run: (_) {
          nativeCalls++;
          return 1;
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('could not be read'),
        ),
      ),
    );
    expect(
      nativeCalls,
      0,
      reason:
          'GTCRN builds a resampler from the sample rate and divides by '
          'it — the c0000094 in the field report.',
    );
  });

  test('a silent recording never reaches GTCRN', () {
    var nativeCalls = 0;

    expect(
      () => denoiseSafeWave<int>(
        'clip.wav',
        readWave: (_) => wave(sampleCount: 0, sampleRate: 16000),
        run: (_) {
          nativeCalls++;
          return 1;
        },
      ),
      throwsStateError,
    );
    expect(nativeCalls, 0);
  });

  test('a real recording is denoised and its result returned', () {
    final seen = <int>[];

    final result = denoiseSafeWave<String>(
      'clip.wav',
      readWave: (_) => wave(sampleCount: 16000, sampleRate: 16000),
      run: (audio) {
        seen.add(audio.samples.length);
        return 'denoised';
      },
    );

    expect(result, 'denoised');
    expect(seen, [16000], reason: 'The decoded wave is passed straight on.');
  });

  test('the refusal is a throw, so denoise() falls back to raw audio', () {
    // denoise() catches everything and returns the original recording;
    // this pins that a refusal takes that path rather than returning a
    // value that would be written over the user's audio.
    expect(
      () => denoiseSafeWave<int>(
        'clip.wav',
        readWave: (_) => wave(sampleCount: 0, sampleRate: 0),
        run: (_) => 1,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
