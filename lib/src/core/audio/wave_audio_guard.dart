/// Why a decoded WAV must not be handed to a native audio engine.
enum WaveAudioProblem {
  /// Nothing was recorded. Proved against the real recognizer: zero
  /// samples makes the encoder's first convolution reject an input shape
  /// of `{0,128}` and abort.
  silent,

  /// The recording could not be read at all. `readWave` does not throw —
  /// a missing, empty or truncated file comes back as a `WaveData` with a
  /// sample rate of zero — and the denoiser then builds a resampler from
  /// that rate and divides by it. That is the `c0000094`
  /// (EXCEPTION_INT_DIVIDE_BY_ZERO) in the field report.
  unreadable,
}

/// The one decision that keeps degenerate audio away from native code, or
/// null when the audio is safe to use.
///
/// A native abort cannot be caught from Dart, so neither case fails —
/// the whole app vanishes, with no error, no toast and no history entry.
WaveAudioProblem? waveAudioProblem({
  required int sampleCount,
  required int sampleRate,
}) {
  // Checked first: a truncated file reports both, and reporting it as
  // silence would tell the user they said nothing when the real answer is
  // that the recording was lost.
  if (sampleRate <= 0) {
    return WaveAudioProblem.unreadable;
  }
  if (sampleCount == 0) {
    return WaveAudioProblem.silent;
  }
  return null;
}

/// Calls [run] only when the audio is safe for native code, and [refuse]
/// otherwise.
///
/// The native call is a parameter on purpose. The behaviour this exists to
/// create is "the native call does not happen for degenerate audio", and
/// passing the call in is what makes that assertable without loading a
/// model over FFI. An `if` guard sitting above an inline native call reads
/// the same but can be deleted with every test still green — which is
/// exactly how the denoiser ended up unguarded while the recognizer was
/// not.
///
/// Callers differ in what refusal means (the recognizer answers with an
/// empty transcript, the denoiser throws so the raw recording is used), so
/// the policy stays with them and only the decision is shared.
T runOnSafeWave<T>({
  required int sampleCount,
  required int sampleRate,
  required T Function() run,
  required T Function(WaveAudioProblem problem) refuse,
}) {
  final problem = waveAudioProblem(
    sampleCount: sampleCount,
    sampleRate: sampleRate,
  );
  return problem == null ? run() : refuse(problem);
}
