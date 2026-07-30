import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../utils/text_metrics.dart';
import '../../audio/audio_recorder.dart';
import '../../audio/microphone_audio_recorder_factory.dart'
    show AudioRecorderFactory;
import '../../audio/microphone_discovery.dart';
import '../../stt/stt_engine.dart';
import '../../stt/stt_model_provisioner.dart';

/// The channel the Kotlin accessibility service (the floating mic and
/// the physical-keyboard shortcut) uses to drive dictation in the
/// headless Flutter engine it hosts.
const nativeDictationChannelName = 'typemate/dictation';

/// Error codes the native surfaces map to short status toasts. An
/// overlay cannot show dialogs or start downloads; anything that needs
/// the full app tells the user to open it.
class NativeDictationErrorCodes {
  static const modelMissing = 'model-missing';
  static const recordFailed = 'record-failed';
  static const transcribeFailed = 'transcribe-failed';
}

/// Dictation for the native surfaces: hold the mic bubble or the
/// desktop shortcut (start), release (stop) — the transcript comes back
/// over the channel and the service inserts it into the focused field
/// of whatever app the user is in.
///
/// Deliberately leaner than [DictationController]: no history and no
/// denoiser — the bubble is the status UI, and recordings follow the
/// same transcribe-and-delete privacy contract.
class NativeDictationHandler {
  NativeDictationHandler({
    required this.engine,
    required this.recorderFactory,
    this.provisioner,
    this.onTranscriptGenerated,
  });

  final SttEngine engine;
  final AudioRecorderFactory recorderFactory;

  /// Model presence gate; null means the engine needs no provisioning
  /// (tests).
  final SttModelProvisioner? provisioner;

  /// Lands successful dictations in the app's history, so the floating
  /// mic feeds the same list (and Insights) as in-app dictation.
  final Future<void> Function(String transcript, {required Duration duration})?
  onTranscriptGenerated;

  /// Base allowance on top of the clip's own length; decoding runs at
  /// roughly realtime or faster (mirrors DictationController's policy).
  static const baseTranscribeTimeout = Duration(seconds: 15);
  static const maxTranscribeTimeout = Duration(minutes: 2);

  AudioRecorder? _activeRecorder;

  /// Loads the model as soon as a text field gains focus, so the first
  /// dictation skips the cold load. Quietly does nothing when the model
  /// is not provisioned; that surfaces properly on the first hold.
  Future<void> warmUp() async {
    final provisioner = this.provisioner;
    if (provisioner != null && !provisioner.isReady) {
      await provisioner.refresh();
      if (!provisioner.isReady) {
        return;
      }
    }
    try {
      await engine.prepare();
    } catch (_) {
      // Best-effort; a real failure is reported by the next dictation.
    }
  }

  Future<void> start() async {
    if (_activeRecorder != null) {
      return;
    }
    final provisioner = this.provisioner;
    if (provisioner != null && !provisioner.isReady) {
      await provisioner.refresh();
      if (!provisioner.isReady) {
        throw PlatformException(
          code: NativeDictationErrorCodes.modelMissing,
          message: 'Open TypeMate to download the speech model',
        );
      }
    }
    final recorder = recorderFactory.create(
      const MicrophoneDevice(name: 'System default microphone'),
    );
    _activeRecorder = recorder;
    try {
      await recorder.start();
    } catch (error) {
      _activeRecorder = null;
      throw PlatformException(
        code: NativeDictationErrorCodes.recordFailed,
        message: 'Microphone unavailable',
        details: '$error',
      );
    }
  }

  /// A stalled recorder must not hang stop() forever (which would wedge
  /// the bubble in "Transcribing..."); stopping is a local call that
  /// returns in milliseconds normally.
  static const _recorderStopTimeout = Duration(seconds: 10);

  /// Stops recording and returns the transcript; '' for silence or when
  /// nothing was recording.
  Future<String> stop() async {
    final recorder = _activeRecorder;
    _activeRecorder = null;
    if (recorder == null) {
      return '';
    }
    final AudioRecording recording;
    try {
      recording = await recorder.stop().timeout(_recorderStopTimeout);
    } catch (error) {
      throw PlatformException(
        code: NativeDictationErrorCodes.recordFailed,
        message: 'Recording did not stop',
        details: '$error',
      );
    }
    try {
      final timeout = _timeoutFor(recording.duration);
      final transcript = (await engine.transcribe(recording).timeout(timeout))
          .trim();
      if (isSilentAudioTranscript(transcript)) {
        return '';
      }
      if (transcript.isNotEmpty) {
        try {
          await onTranscriptGenerated?.call(
            transcript,
            duration: recording.duration,
          );
        } catch (_) {
          // History is bookkeeping; a failed write must not block the
          // transcript from reaching the field.
        }
      }
      return transcript;
    } catch (error) {
      throw PlatformException(
        code: NativeDictationErrorCodes.transcribeFailed,
        message: 'Could not transcribe',
        details: '$error',
      );
    } finally {
      _discardRecording(recording);
    }
  }

  /// Stops and throws the audio away (surface dismissed mid-hold).
  Future<void> cancel() async {
    final recorder = _activeRecorder;
    _activeRecorder = null;
    if (recorder == null) {
      return;
    }
    try {
      _discardRecording(await recorder.stop());
    } catch (_) {
      // Cancellation is best-effort; the startup purge sweeps leftovers.
    }
  }

  /// Frees the resident model when the last native surface goes away.
  Future<void> shutdown() async {
    await cancel();
    final engine = this.engine;
    if (engine is DisposableSttEngine) {
      await engine.shutdown();
    }
  }

  Duration _timeoutFor(Duration recordingDuration) {
    final scaled = baseTranscribeTimeout + recordingDuration;
    return scaled > maxTranscribeTimeout ? maxTranscribeTimeout : scaled;
  }

  void _discardRecording(AudioRecording recording) {
    if (recording.path.isEmpty) {
      return;
    }
    try {
      // Synchronous on purpose, matching the rest of the audio path.
      final file = File(recording.path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best effort; the main app's startup purge sweeps leftovers.
    }
  }
}

/// Wires [handler] to the platform channel the Kotlin service calls.
void registerNativeDictationChannel(
  NativeDictationHandler handler, {
  MethodChannel channel = const MethodChannel(nativeDictationChannelName),
}) {
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'warmUp':
        await handler.warmUp();
        return null;
      case 'startDictation':
        await handler.start();
        return null;
      case 'stopDictation':
        return handler.stop();
      case 'cancelDictation':
        await handler.cancel();
        return null;
      case 'shutdown':
        await handler.shutdown();
        return null;
      default:
        throw MissingPluginException(
          'Unknown dictation method: ${call.method}',
        );
    }
  });
}
