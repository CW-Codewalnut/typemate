/// Why a decoded WAV must not be handed to a native audio engine, or null
/// when it is safe to use.
///
/// Both sherpa engines abort the PROCESS on degenerate input, and a native
/// abort cannot be caught from Dart — the app simply vanishes, with no
/// error, no toast and no history entry:
///
/// * zero samples: the recognizer's first convolution gets an invalid
///   input shape (`{0,128}`);
/// * a sample rate of zero: the denoiser builds a resampler and divides by
///   zero. This is the `c0000094` seen in the field, and it is what an
///   unreadable file produces, because `readWave` does not throw — a
///   missing, empty or truncated file comes back as an empty `WaveData`.
///
/// Shared by the denoiser and the recognizer worker on purpose: noise
/// suppression runs FIRST and is on by default, so guarding only the
/// recognizer left the reported crash wide open.
///
/// Returns an empty string when nothing was spoken, so callers can answer
/// with an empty transcript, and a non-empty reason when the recording
/// could not be read at all — a real failure the user should be able to
/// retry from History rather than be told they said nothing.
String? waveAudioRefusal({required int sampleCount, required int sampleRate}) {
  if (sampleRate <= 0) {
    return 'the recording could not be read';
  }
  if (sampleCount == 0) {
    return '';
  }
  return null;
}
