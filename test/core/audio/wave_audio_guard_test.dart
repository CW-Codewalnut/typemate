import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/wave_audio_guard.dart';

/// The one decision that keeps degenerate audio away from native code.
///
/// Both callers ask this before handing a decoded WAV to sherpa: the
/// denoiser isolate (`_denoiseInPlace`) and the Parakeet recognizer worker
/// (`_workerMain`). Neither can be exercised from a unit test — each needs
/// a real model over FFI — so the decision they share is tested here, and
/// they are each a single call to it.
///
/// Both refusals were proved against the real library: zero samples dies
/// with 'Invalid input shape: {0,128}', and a zero sample rate dies
/// building a resampler, the c0000094 divide-by-zero in the field report.
/// A native abort cannot be caught from Dart, so the app simply vanishes —
/// no error, no toast, no history entry.
void main() {
  group('waveAudioRefusal', () {
    test('silence is refused as an empty transcript', () {
      expect(waveAudioRefusal(sampleCount: 0, sampleRate: 16000), isEmpty);
    });

    test('an unreadable recording is refused as a real failure', () {
      // readWave reports sampleRate 0 for a missing, empty or truncated
      // file. That is not silence: the user should be able to retry it
      // from History rather than be told they said nothing.
      final reason = waveAudioRefusal(sampleCount: 0, sampleRate: 0);
      expect(reason, isNotEmpty);
      expect(reason, contains('could not be read'));
    });

    test('an unreadable recording outranks the silence answer', () {
      // A truncated file reports both zero samples and a zero rate. It
      // must not be reported as silence: that would swallow a real
      // failure and tell the user they said nothing.
      expect(waveAudioRefusal(sampleCount: 0, sampleRate: 0), isNotEmpty);
    });

    test('a negative sample rate is refused too', () {
      expect(waveAudioRefusal(sampleCount: 16000, sampleRate: -1), isNotEmpty);
    });

    test('a normal recording is allowed through', () {
      expect(waveAudioRefusal(sampleCount: 16000, sampleRate: 16000), isNull);
    });

    test('short audio is allowed through', () {
      // A 10ms clip decodes fine against the real recognizer; only zero
      // is fatal, so the guard must not reject short audio.
      expect(waveAudioRefusal(sampleCount: 160, sampleRate: 16000), isNull);
    });
  });
}
