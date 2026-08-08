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
    // Run the isolate by hand rather than Isolate.run, so a timeout can
    // actually kill it. Isolate.run's timeout only stops waiting: the
    // isolate keeps going and can renameSync its output over the recording
    // after transcription has already started reading it.
    final done = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(
        _denoiseEntryPoint,
        _DenoiseRequest(model, wavPath, done.sendPort),
        onError: done.sendPort,
        onExit: done.sendPort,
        debugName: 'typemate-denoise',
      );
      final result = await done.first.timeout(timeout);
      if (result is List) {
        throw StateError('${result.first}');
      }
    } catch (error) {
      debugPrint(
        'TypeMate: noise suppression failed, using the raw recording: $error',
      );
      _deleteQuietly(File(_denoisedPathFor(wavPath)));
    } finally {
      worker?.kill(priority: Isolate.immediate);
      done.close();
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
/// What the denoise isolate needs, plus where to report completion.
class _DenoiseRequest {
  const _DenoiseRequest(this.modelPath, this.wavPath, this.donePort);

  final String modelPath;
  final String wavPath;
  final SendPort donePort;
}

/// Isolate entry: denoise, then report. A throw here arrives on the same
/// port through onError, so the caller sees every outcome.
void _denoiseEntryPoint(_DenoiseRequest request) {
  _denoiseInPlace(request.modelPath, request.wavPath);
  request.donePort.send(null);
}

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
    // GTCRN runs BEFORE transcription and noise suppression is on by
    // default, so this is the first native code a bad recording reaches —
    // guarding only the recognizer left the reported crash in place.
    // readWave never throws: an unreadable file (missing, 0 bytes,
    // truncated header) comes back with sampleRate 0, and sherpa builds a
    // resampler from it, dividing by zero. That abort is EXACTLY the
    // c0000094 in the field report; it kills the process, and the isolate
    // does not contain it. Throwing here is caught by denoise(), which
    // falls back to the raw recording.
    if (wave.sampleRate <= 0) {
      throw StateError('recording could not be read: $wavPath');
    }
    if (wave.samples.isEmpty) {
      throw StateError('recording contains no audio: $wavPath');
    }
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
