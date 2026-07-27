import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'audio/audio_recorder.dart';
import '../models/dictation_state.dart';
import '../utils/text_metrics.dart';
import 'platform/dictation_sounds.dart';
import 'platform/platform_bridge.dart';
import 'stt/stt_engine.dart';

typedef AudioRecorderProvider = AudioRecorder? Function();
typedef TranscriptGeneratedCallback =
    Future<void> Function(String transcript, {Duration duration});
typedef TranscriptionFailedCallback =
    Future<void> Function(
      String reason, {
      String? recordingPath,
      Duration duration,
    });

class DictationController extends ChangeNotifier {
  factory DictationController({
    required PlatformBridge platformBridge,
    required SttEngine sttEngine,
    AudioRecorder? audioRecorder,
    AudioRecorderProvider? audioRecorderProvider,
    TranscriptGeneratedCallback? onTranscriptGenerated,
    TranscriptionFailedCallback? onTranscriptionFailed,
    Duration transcribeTimeout = defaultTranscribeTimeout,
    Duration recorderStopTimeout = defaultRecorderStopTimeout,
    DictationSoundPlayer? startSoundPlayer,
    DictationSoundPlayer? failureSoundPlayer,
  }) {
    assert(
      audioRecorder != null || audioRecorderProvider != null,
      'Provide either audioRecorder or audioRecorderProvider.',
    );

    return DictationController._(
      platformBridge,
      sttEngine,
      audioRecorderProvider ?? (() => audioRecorder!),
      onTranscriptGenerated,
      onTranscriptionFailed,
      transcribeTimeout,
      recorderStopTimeout,
      startSoundPlayer ?? playDictationStartSound,
      failureSoundPlayer ?? playDictationFailureSound,
    );
  }

  DictationController._(
    this._platformBridge,
    this._sttEngine,
    this._audioRecorderProvider,
    this._onTranscriptGenerated,
    this._onTranscriptionFailed,
    this._transcribeTimeout,
    this._recorderStopTimeout,
    this._startSoundPlayer,
    this._failureSoundPlayer,
  );

  /// Base allowance for a transcription; the recording's own length is
  /// added on top (decoding runs at roughly realtime or faster), capped at
  /// [maxTranscribeTimeout]. A 5s clip fails fast (~20s) instead of
  /// sitting on a long flat watchdog, while a two-minute dictation on a
  /// slow laptop still gets room to finish. If the timeout fires during a
  /// speech-server cold start, the server keeps warming in the background,
  /// so an immediate retry usually succeeds.
  static const defaultTranscribeTimeout = Duration(seconds: 15);

  /// Upper bound for the duration-scaled transcription timeout.
  static const maxTranscribeTimeout = Duration(minutes: 2);

  /// Stopping the recorder is a local plugin call that normally returns in
  /// milliseconds; a hang here means the audio backend died mid-recording.
  static const defaultRecorderStopTimeout = Duration(seconds: 10);

  final PlatformBridge _platformBridge;
  final SttEngine _sttEngine;
  final AudioRecorderProvider _audioRecorderProvider;
  final TranscriptGeneratedCallback? _onTranscriptGenerated;
  final TranscriptionFailedCallback? _onTranscriptionFailed;
  final Duration _transcribeTimeout;
  final Duration _recorderStopTimeout;
  final DictationSoundPlayer _startSoundPlayer;
  final DictationSoundPlayer _failureSoundPlayer;

  /// User-facing failure copy: plain words, no runtime internals. The
  /// History pointer is appended only to the OS notification — inside the
  /// app the user is already looking at History.
  static const failedToStartRecordingMessage =
      'Couldn\'t start recording. Check that your microphone is connected and allowed, then try again.';
  static const failedToFinishRecordingMessage =
      'Couldn\'t capture your voice. Check your microphone and try again.';
  static const transcriptionFailedMessage =
      'Couldn\'t turn your speech into text.';
  static const transcriptionTimeoutMessage =
      'Transcription took too long and was stopped.';
  static const retryFromHistoryHint = ' You can retry it from History.';
  static const insertionFailedMessage =
      'Your text is ready but couldn\'t be typed into the app you were using. Copy it from History.';

  AudioRecorder? _activeRecorder;
  DictationPhase _phase = DictationPhase.idle;
  String _latestTranscript = '';
  String _statusMessage = 'Ready to set up local dictation.';
  String? _errorMessage;

  DictationPhase get phase => _phase;
  String get latestTranscript => _latestTranscript;
  String get statusMessage => _statusMessage;

  /// Why the last dictation failed, kept until the next attempt starts.
  /// The overlay's failure flash lasts seconds; this stays visible in the
  /// window for whenever the user opens it.
  String? get errorMessage => _errorMessage;

  bool get isBusy => _phase != DictationPhase.idle;

  Future<void> prepare() async {
    _setPhase(DictationPhase.preparing, 'Preparing local speech engine...');
    try {
      await _sttEngine.prepare();
    } catch (_) {
      _setPhase(
        DictationPhase.idle,
        'Unable to prepare local speech engine. Check the speech runtime and model file, then try again.',
      );
      return;
    }
    _setPhase(DictationPhase.idle, 'Ready. Hold the shortcut and speak.');
  }

  Future<void> startListening() async {
    if (_phase != DictationPhase.idle) {
      return;
    }

    _latestTranscript = '';
    _errorMessage = null;
    final recorder = _audioRecorderProvider();
    if (recorder == null) {
      _statusMessage = 'Select a microphone before dictating.';
      notifyListeners();
      return;
    }

    _setPhase(DictationPhase.listening, 'Listening while shortcut is held...');
    _activeRecorder = recorder;

    try {
      await _platformBridge.showListeningOverlay();
      try {
        // The rising chime marks listening — previously played by the
        // native overlays, now one Dart implementation for all platforms.
        await _startSoundPlayer();
      } catch (_) {
        // Sound is a garnish; the dictation continues without it.
      }
      await recorder.start();
    } catch (error) {
      _activeRecorder = null;
      debugPrint('TypeMate: unable to start recording: $error');
      await _failDictation(failedToStartRecordingMessage);
    }
  }

  /// Every path through here must end back in an idle phase: a phase left
  /// stuck at listening/transcribing keeps the overlay up forever and makes
  /// [startListening] ignore every later shortcut press, which reads as
  /// "TypeMate keeps transcribing" with no error.
  Future<void> stopListening() async {
    if (_phase != DictationPhase.listening) {
      return;
    }

    final recorder = _activeRecorder;
    late final AudioRecording recording;
    try {
      recording = recorder == null
          ? const AudioRecording(path: '', duration: Duration.zero)
          : await recorder.stop().timeout(_recorderStopTimeout);
    } catch (_) {
      _activeRecorder = null;
      await _failDictation(failedToFinishRecordingMessage);
      return;
    }
    _activeRecorder = null;

    try {
      await _platformBridge.showTranscribingOverlay();
    } catch (_) {
      // The overlay is informational; transcription proceeds without it.
    }
    _setPhase(DictationPhase.transcribing, 'Transcribing locally...');

    final String transcript;
    try {
      transcript = await _sttEngine
          .transcribe(recording)
          .timeout(transcribeTimeoutFor(recording.duration));
    } on TimeoutException {
      await _failTranscription(recording, transcriptionTimeoutMessage);
      return;
    } catch (error) {
      debugPrint('TypeMate: transcription failed: $error');
      await _failTranscription(recording, transcriptionFailedMessage);
      return;
    }
    // Audio does not outlive a completed transcription: dictation is
    // private, so successful and silent WAVs are discarded immediately.
    // Only a FAILED dictation keeps its recording (moved aside in
    // _failTranscription) so the user can retry it from History; even that
    // copy is deleted on retry, eviction, clear, or after 30 unused days.
    _discardRecording(recording);
    final usableTranscript = _normalizeTranscript(transcript);
    if (usableTranscript.isEmpty) {
      _latestTranscript = '';
      await _hideOverlayQuietly();
      _setPhase(
        DictationPhase.idle,
        'Silent audio. Ready for the next dictation.',
      );
      return;
    }
    _latestTranscript = usableTranscript;
    try {
      await _onTranscriptGenerated?.call(
        usableTranscript,
        duration: recording.duration,
      );
    } catch (error) {
      // History is bookkeeping; a failed write must not block insertion or
      // strand the transcribing overlay.
      debugPrint('TypeMate: unable to store dictation history: $error');
    }

    _setPhase(DictationPhase.inserting, 'Inserting into focused text field...');
    try {
      await _platformBridge.insertTextIntoFocusedField(usableTranscript);
    } catch (_) {
      await _failDictation(insertionFailedMessage);
      return;
    }

    await _hideOverlayQuietly();
    _setPhase(
      DictationPhase.idle,
      'Inserted transcript. Ready for the next dictation.',
    );
  }

  /// Recording length plus a base allowance, capped: decoding runs at
  /// roughly realtime or faster, so a short clip fails fast instead of
  /// sitting on a long flat watchdog.
  @visibleForTesting
  Duration transcribeTimeoutFor(Duration recordingDuration) {
    final scaled = _transcribeTimeout + recordingDuration;
    return scaled > maxTranscribeTimeout ? maxTranscribeTimeout : scaled;
  }

  /// Single funnel for every failed dictation: hide the overlay, post an
  /// OS notification (readable later from the Action Center), land back in
  /// idle. The overlay shows no error state of its own — the notification
  /// and the failed History entry carry it.
  Future<void> _failDictation(
    String message, {
    String? notificationMessage,
  }) async {
    _errorMessage = message;
    await _hideOverlayQuietly();
    try {
      // A falling tone — the audible inverse of the start chime — so the
      // failure is heard even without looking at the screen.
      await _failureSoundPlayer();
    } catch (_) {
      // Sound is a garnish; never let it strand the phase.
    }
    try {
      await _platformBridge.showDictationFailureNotification(
        notificationMessage ?? message,
      );
    } catch (_) {
      // Best effort; a broken notifier must never strand the phase.
    }
    _setPhase(DictationPhase.idle, message);
  }

  /// A transcription failure additionally keeps the recording so the user
  /// can retry it from History. The WAV moves into a `failed` subfolder,
  /// which the startup purge leaves alone.
  Future<void> _failTranscription(
    AudioRecording recording,
    String message,
  ) async {
    String? keptPath;
    try {
      final original = File(recording.path);
      if (recording.path.isNotEmpty && original.existsSync()) {
        final failedDirectory = Directory(
          '${original.parent.path}${Platform.pathSeparator}failed',
        )..createSync(recursive: true);
        keptPath = original
            .renameSync(
              '${failedDirectory.path}${Platform.pathSeparator}${original.uri.pathSegments.last}',
            )
            .path;
      }
    } catch (_) {
      // If the recording cannot be kept the failure is still reported;
      // there is just nothing to retry.
      keptPath = null;
      _discardRecording(recording);
    }
    try {
      await _onTranscriptionFailed?.call(
        message,
        recordingPath: keptPath,
        duration: recording.duration,
      );
    } catch (error) {
      debugPrint('TypeMate: unable to record failed dictation: $error');
    }
    // The toast is read outside the app, so it points at History — the
    // in-app surfaces are already there.
    await _failDictation(
      message,
      notificationMessage: keptPath == null
          ? message
          : '$message$retryFromHistoryHint',
    );
  }

  /// Re-transcribes a recording kept from a failed dictation. Returns the
  /// normalized transcript ('' for silence) or null when transcription
  /// failed again; [errorMessage] then carries the reason. No overlay is
  /// involved — the user is looking at the app.
  Future<String?> retryTranscription(
    String recordingPath, {
    Duration duration = Duration.zero,
  }) async {
    if (_phase != DictationPhase.idle) {
      return null;
    }
    _errorMessage = null;
    _setPhase(DictationPhase.transcribing, 'Retrying transcription...');
    final String transcript;
    try {
      transcript = await _sttEngine
          .transcribe(AudioRecording(path: recordingPath, duration: duration))
          .timeout(transcribeTimeoutFor(duration));
    } on TimeoutException {
      _errorMessage = transcriptionTimeoutMessage;
      _setPhase(DictationPhase.idle, transcriptionTimeoutMessage);
      return null;
    } catch (error) {
      debugPrint('TypeMate: retry transcription failed: $error');
      _errorMessage = transcriptionFailedMessage;
      _setPhase(DictationPhase.idle, transcriptionFailedMessage);
      return null;
    }
    final usableTranscript = _normalizeTranscript(transcript);
    _latestTranscript = usableTranscript;
    _setPhase(
      DictationPhase.idle,
      usableTranscript.isEmpty
          ? 'That recording had no speech in it.'
          : 'Transcription recovered. Copy it from History.',
    );
    return usableTranscript;
  }

  Future<void> _hideOverlayQuietly() async {
    try {
      await _platformBridge.hideListeningOverlay();
    } catch (_) {
      // A stuck overlay must never strand the dictation phase.
    }
  }

  Future<void> toggleListening() async {
    if (_phase == DictationPhase.listening) {
      await stopListening();
    } else if (_phase == DictationPhase.idle) {
      await startListening();
    }
  }

  void _setPhase(DictationPhase phase, String message) {
    _phase = phase;
    _statusMessage = message;
    notifyListeners();
  }

  void _discardRecording(AudioRecording recording) {
    if (recording.path.isEmpty) {
      return;
    }
    try {
      // Synchronous on purpose: async file IO never completes inside the
      // widget-test fake-async zone, deadlocking any test that dictates.
      final file = File(recording.path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best effort; a locked file is retried by the startup purge.
    }
  }

  String _normalizeTranscript(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty || isSilentAudioTranscript(normalized)) {
      return '';
    }
    return normalized;
  }
}
