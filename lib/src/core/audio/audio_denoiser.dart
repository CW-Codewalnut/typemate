import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../stt/whisper_cli_stt_engine.dart'
    show DartSttProcessRunner, SttProcessRunner;
import 'audio_recorder.dart';

/// Cleans steady background noise out of a finished recording before it is
/// transcribed. Implementations never throw and never lose the recording:
/// on any failure the original audio is returned untouched, because a noisy
/// transcription always beats a failed dictation.
abstract interface class AudioDenoiser {
  Future<AudioRecording> denoise(AudioRecording recording);
}

/// Denoises a WAV in place with the bundled sherpa-onnx offline denoiser
/// running the GTCRN speech-enhancement model (16 kHz, matching the
/// recorder's capture format).
///
/// The cleaned audio replaces the original file at the same path, so
/// everything downstream — transcription, the failed-recording keep/retry
/// flow, and cleanup — keeps operating on the single recording path.
class SherpaGtcrnAudioDenoiser implements AudioDenoiser {
  SherpaGtcrnAudioDenoiser({
    required this.executable,
    required this.modelPath,
    SttProcessRunner? processRunner,
    this.timeout = defaultTimeout,
  }) : processRunner = processRunner ?? const DartSttProcessRunner();

  /// GTCRN runs at well under 0.1x realtime, so even a two-minute dictation
  /// finishes in seconds; a run that hits this bound is hung.
  static const defaultTimeout = Duration(seconds: 15);

  final String executable;
  final String modelPath;
  final SttProcessRunner processRunner;
  final Duration timeout;

  @override
  Future<AudioRecording> denoise(AudioRecording recording) async {
    if (recording.path.isEmpty) {
      return recording;
    }
    final outputPath = '${recording.path}.denoised.wav';
    try {
      final result = await processRunner
          .run(executable, [
            '--speech-denoiser-gtcrn-model=$modelPath',
            '--input-wav=${recording.path}',
            '--output-wav=$outputPath',
          ])
          .timeout(timeout);
      final output = File(outputPath);
      if (result.exitCode != 0 || !output.existsSync()) {
        debugPrint(
          'TypeMate: noise suppression exited with ${result.exitCode}; '
          'using the raw recording. ${result.diagnostics}',
        );
        _deleteQuietly(output);
        return recording;
      }
      output.renameSync(recording.path);
      return recording;
    } catch (error) {
      debugPrint(
        'TypeMate: noise suppression failed, using the raw recording: $error',
      );
      _deleteQuietly(File(outputPath));
      return recording;
    }
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
