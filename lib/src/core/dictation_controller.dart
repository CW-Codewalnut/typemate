import 'package:flutter/foundation.dart';

import '../audio/audio_recorder.dart';
import '../models/dictation_state.dart';
import '../platform/platform_bridge.dart';
import '../stt/stt_engine.dart';

class DictationController extends ChangeNotifier {
  DictationController({
    required PlatformBridge platformBridge,
    required SttEngine sttEngine,
    required AudioRecorder audioRecorder,
  }) : this._(platformBridge, sttEngine, audioRecorder);

  DictationController._(
    this._platformBridge,
    this._sttEngine,
    this._audioRecorder,
  );

  final PlatformBridge _platformBridge;
  final SttEngine _sttEngine;
  final AudioRecorder _audioRecorder;

  DictationPhase _phase = DictationPhase.idle;
  String _latestTranscript = '';
  String _statusMessage = 'Ready to set up local dictation.';

  DictationPhase get phase => _phase;
  String get latestTranscript => _latestTranscript;
  String get statusMessage => _statusMessage;
  bool get isBusy => _phase != DictationPhase.idle;

  Future<void> prepare() async {
    _setPhase(DictationPhase.preparing, 'Preparing local speech engine...');
    await _sttEngine.prepare();
    _setPhase(DictationPhase.idle, 'Ready. Hold the shortcut and speak.');
  }

  Future<void> startListening() async {
    if (_phase != DictationPhase.idle) {
      return;
    }

    _latestTranscript = '';
    _setPhase(DictationPhase.listening, 'Listening while shortcut is held...');
    await _platformBridge.showListeningOverlay();
    await _audioRecorder.start();
  }

  Future<void> stopListening() async {
    if (_phase != DictationPhase.listening) {
      return;
    }

    final recording = await _audioRecorder.stop();
    await _platformBridge.hideListeningOverlay();
    _setPhase(DictationPhase.transcribing, 'Transcribing locally...');

    final transcript = await _sttEngine.transcribe(recording);
    _latestTranscript = transcript;

    _setPhase(DictationPhase.inserting, 'Inserting into focused text field...');
    await _platformBridge.insertTextIntoFocusedField(transcript);

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
}
