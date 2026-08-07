import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'audio_recorder.dart';

/// Cleans steady background noise out of a finished recording before it is
/// transcribed. Implementations never throw and never lose the recording:
/// on any failure the original audio is returned untouched, because a noisy
/// transcription always beats a failed dictation.
abstract interface class AudioDenoiser {
  Future<AudioRecording> denoise(AudioRecording recording);
}

/// Denoises a WAV in place with the GTCRN speech-enhancement model through
/// the sherpa_onnx plugin — the same in-process FFI route the English
/// engine uses; no helper executable involved.
///
/// The cleaned audio replaces the original file at the same path, so
/// everything downstream — transcription, the failed-recording keep/retry
/// flow, and cleanup — keeps operating on the single recording path.
///
/// The blocking FFI work (model load + inference) runs in a short-lived
/// isolate so it never janks the UI; GTCRN is ~0.5 MB, so the per-call
/// load costs milliseconds.
class SherpaGtcrnAudioDenoiser implements AudioDenoiser {
  SherpaGtcrnAudioDenoiser({
    required this.modelPathCandidates,
    this.timeout = defaultTimeout,
  }) {
    // A real check, not an assert: asserts are stripped in release, and an
    // empty list would surface as a confusing StateError from firstWhere
    // mid-dictation rather than at construction.
    if (modelPathCandidates.isEmpty) {
      throw ArgumentError.value(
        modelPathCandidates,
        'modelPathCandidates',
        'needs at least one path to look for the GTCRN model',
      );
    }
  }

  /// GTCRN runs at well under 0.1x realtime, so even a two-minute dictation
  /// finishes in seconds; a run that hits this bound is hung.
  static const defaultTimeout = Duration(seconds: 15);

  /// Where the GTCRN model may live, first existing wins: a bundled
  /// install has exactly one location, but on Android the model rides
  /// whichever Parakeet download (English unified or multilingual v3) happened
  /// first, so both directories are candidates. Checked per call because
  /// the download can complete after this object is built.
  final List<String> modelPathCandidates;
  final Duration timeout;

  @override
  Future<AudioRecording> denoise(AudioRecording recording) async {
    if (recording.path.isEmpty) {
      return recording;
    }
    final model = modelPathCandidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => modelPathCandidates.first,
    );
    final wavPath = recording.path;
    try {
      await Isolate.run(() => _denoiseInPlace(model, wavPath)).timeout(timeout);
    } catch (error) {
      debugPrint(
        'TypeMate: noise suppression failed, using the raw recording: $error',
      );
      _deleteQuietly(File(_denoisedPathFor(wavPath)));
    }
    return recording;
  }

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // A stray temp file is swept by the startup recordings purge.
    }
  }
}

String _denoisedPathFor(String wavPath) => '$wavPath.denoised.wav';

/// Isolate entry: loads GTCRN, denoises the WAV, and atomically replaces
/// the original. Any throw is reported back to [SherpaGtcrnAudioDenoiser]
/// as the isolate error and handled there.
void _denoiseInPlace(String modelPath, String wavPath) {
  sherpa_onnx.initBindings();
  final denoiser = sherpa_onnx.OfflineSpeechDenoiser(
    sherpa_onnx.OfflineSpeechDenoiserConfig(
      model: sherpa_onnx.OfflineSpeechDenoiserModelConfig(
        gtcrn: sherpa_onnx.OfflineSpeechDenoiserGtcrnModelConfig(
          model: modelPath,
        ),
      ),
    ),
  );
  try {
    final wave = sherpa_onnx.readWave(wavPath);
    final denoised = denoiser.run(
      samples: wave.samples,
      sampleRate: wave.sampleRate,
    );
    if (denoised.samples.isEmpty) {
      throw StateError('the denoiser produced no audio');
    }
    final outputPath = _denoisedPathFor(wavPath);
    if (!sherpa_onnx.writeWave(
      filename: outputPath,
      samples: denoised.samples,
      sampleRate: denoised.sampleRate,
    )) {
      throw StateError('could not write the denoised WAV');
    }
    File(outputPath).renameSync(wavPath);
  } finally {
    denoiser.free();
  }
}
