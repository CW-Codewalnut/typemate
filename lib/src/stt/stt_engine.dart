import '../audio/audio_recorder.dart';

abstract interface class SttEngine {
  Future<bool> isReady();

  Future<void> prepare();

  Future<String> transcribe(AudioRecording recording);
}
