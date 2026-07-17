import 'dart:io';

import 'package:flutter/foundation.dart';

import 'audio/audio_recorder.dart';
import '../models/dictation_state.dart';
import '../utils/text_metrics.dart';
import 'platform/platform_bridge.dart';
import 'stt/stt_engine.dart';

typedef AudioRecorderProvider = AudioRecorder? Function();
typedef TranscriptGeneratedCallback =
    Future<void> Function(String transcript, {Duration duration});

class DictationController extends ChangeNotifier {
  factory DictationController({
    required PlatformBridge platformBridge,
    required SttEngine sttEngine,
    AudioRecorder? audioRecorder,
    AudioRecorderProvider? audioRecorderProvider,
    TranscriptGeneratedCallback? onTranscriptGenerated,
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
    );
  }

  DictationController._(
    this._platformBridge,
    this._sttEngine,
    this._audioRecorderProvider,
    this._onTranscriptGenerated,
  );

  final PlatformBridge _platformBridge;
  final SttEngine _sttEngine;
  final AudioRecorderProvider _audioRecorderProvider;
  final TranscriptGeneratedCallback? _onTranscriptGenerated;

  AudioRecorder? _activeRecorder;
  DictationPhase _phase = DictationPhase.idle;
  String _latestTranscript = '';
  String _statusMessage = 'Ready to set up local dictation.';

  DictationPhase get phase => _phase;
  String get latestTranscript => _latestTranscript;
  String get statusMessage => _statusMessage;
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
      await recorder.start();
    } catch (_) {
      _activeRecorder = null;
      await _platformBridge.hideListeningOverlay();
      _setPhase(
        DictationPhase.idle,
        'Unable to start recording. Check the microphone and its permissions, then try again.',
      );
    }
  }

  Future<void> stopListening() async {
    if (_phase != DictationPhase.listening) {
      return;
    }

    final recorder = _activeRecorder;
    late final AudioRecording recording;
    try {
      recording = recorder == null
          ? const AudioRecording(path: '', duration: Duration.zero)
          : await recorder.stop();
    } catch (_) {
      _activeRecorder = null;
      await _platformBridge.hideListeningOverlay();
      _setPhase(
        DictationPhase.idle,
        'Unable to finish recording. Check the microphone and its permissions, then try again.',
      );
      return;
    }
    _activeRecorder = null;

    await _platformBridge.showTranscribingOverlay();
    _setPhase(DictationPhase.transcribing, 'Transcribing locally...');

    final String transcript;
    try {
      transcript = await _sttEngine.transcribe(recording);
    } catch (_) {
      await _platformBridge.hideListeningOverlay();
      _setPhase(
        DictationPhase.idle,
        'Unable to transcribe locally. Check the speech runtime and model file, then try again.',
      );
      return;
    } finally {
      // Audio never outlives its transcription: dictation is private, so
      // the WAV is discarded whether transcription succeeded or not.
      _discardRecording(recording);
    }
    final usableTranscript = _normalizeTranscript(transcript);
    if (usableTranscript.isEmpty) {
      _latestTranscript = '';
      await _platformBridge.hideListeningOverlay();
      _setPhase(
        DictationPhase.idle,
        'Silent audio. Ready for the next dictation.',
      );
      return;
    }
    _latestTranscript = usableTranscript;
    await _onTranscriptGenerated?.call(
      usableTranscript,
      duration: recording.duration,
    );

    _setPhase(DictationPhase.inserting, 'Inserting into focused text field...');
    try {
      await _platformBridge.insertTextIntoFocusedField(usableTranscript);
    } catch (_) {
      await _platformBridge.hideListeningOverlay();
      _setPhase(
        DictationPhase.idle,
        'Unable to insert text into the focused field. Copy the latest transcript manually and try again.',
      );
      return;
    }

    await _platformBridge.hideListeningOverlay();
    _setPhase(
      DictationPhase.idle,
      'Inserted transcript. Ready for the next dictation.',
    );
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
