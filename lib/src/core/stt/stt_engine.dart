import '../audio/audio_recorder.dart';

abstract interface class SttEngine {
  Future<bool> isReady();

  Future<void> prepare();

  Future<String> transcribe(AudioRecording recording);
}

/// Engines that own background resources (e.g. a resident model server)
/// and must be shut down when the app exits.
abstract interface class DisposableSttEngine implements SttEngine {
  Future<void> shutdown();
}
