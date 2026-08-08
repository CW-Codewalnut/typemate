import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/wave_audio_guard.dart';

/// The one decision that keeps degenerate audio away from native code.
///
/// Both refusals were proved against the real library: zero samples dies
/// with 'Invalid input shape: {0,128}', and a zero sample rate dies
/// building a resampler, the c0000094 divide-by-zero in the field report.
/// A native abort cannot be caught from Dart, so the app simply vanishes —
/// no error, no toast, no history entry.
///
/// The tests that matter here are the ones asserting `run` was NOT called:
/// the behaviour this code exists to create is that the native call does
/// not happen, and a test of the return value alone stays green even if
/// nothing is guarded.
void main() {
  group('waveAudioProblem', () {
    test('silence is reported as silence', () {
      expect(
        waveAudioProblem(sampleCount: 0, sampleRate: 16000),
        WaveAudioProblem.silent,
      );
    });

    test('a zero sample rate is reported as unreadable', () {
      expect(
        waveAudioProblem(sampleCount: 16000, sampleRate: 0),
        WaveAudioProblem.unreadable,
      );
    });

    test('an unreadable recording outranks the silence answer', () {
      // A truncated file reports both zero samples and a zero rate. It
      // must not come back as silence: that would tell the user they said
      // nothing when the recording was actually lost.
      expect(
        waveAudioProblem(sampleCount: 0, sampleRate: 0),
        WaveAudioProblem.unreadable,
      );
    });

    test('a negative sample rate is unreadable too', () {
      expect(
        waveAudioProblem(sampleCount: 16000, sampleRate: -1),
        WaveAudioProblem.unreadable,
      );
    });

    test('normal audio has no problem', () {
      expect(waveAudioProblem(sampleCount: 16000, sampleRate: 16000), isNull);
    });

    test('short audio has no problem', () {
      // A 10ms clip decodes fine against the real recognizer; only zero is
      // fatal, so the guard must not reject short audio.
      expect(waveAudioProblem(sampleCount: 160, sampleRate: 16000), isNull);
    });
  });

  group('runOnSafeWave', () {
    test('never calls the native side for zero samples', () {
      var nativeCalls = 0;
      final problems = <WaveAudioProblem>[];

      runOnSafeWave<String>(
        sampleCount: 0,
        sampleRate: 16000,
        run: () {
          nativeCalls++;
          return 'decoded';
        },
        refuse: (problem) {
          problems.add(problem);
          return '';
        },
      );

      expect(
        nativeCalls,
        0,
        reason: 'Handing zero samples to sherpa aborts the process.',
      );
      expect(problems, [WaveAudioProblem.silent]);
    });

    test('never calls the native side for an unreadable recording', () {
      var nativeCalls = 0;
      final problems = <WaveAudioProblem>[];

      runOnSafeWave<String>(
        sampleCount: 0,
        sampleRate: 0,
        run: () {
          nativeCalls++;
          return 'decoded';
        },
        refuse: (problem) {
          problems.add(problem);
          return '';
        },
      );

      expect(
        nativeCalls,
        0,
        reason: 'A zero sample rate is the c0000094 divide-by-zero.',
      );
      expect(problems, [WaveAudioProblem.unreadable]);
    });

    test('calls the native side once for real audio, and returns it', () {
      var nativeCalls = 0;

      final result = runOnSafeWave<String>(
        sampleCount: 16000,
        sampleRate: 16000,
        run: () {
          nativeCalls++;
          return 'decoded';
        },
        refuse: (problem) => fail('Real audio must not be refused: $problem'),
      );

      expect(nativeCalls, 1);
      expect(result, 'decoded');
    });

    test('a refusal that throws stops the native call', () {
      // The denoiser's policy: refusing throws, which denoise() catches
      // and falls back to the raw recording.
      var nativeCalls = 0;

      expect(
        () => runOnSafeWave<String>(
          sampleCount: 0,
          sampleRate: 0,
          run: () {
            nativeCalls++;
            return 'denoised';
          },
          refuse: (problem) => throw StateError('$problem'),
        ),
        throwsStateError,
      );
      expect(nativeCalls, 0);
    });
  });
}
