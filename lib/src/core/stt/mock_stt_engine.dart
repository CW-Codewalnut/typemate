import '../audio/audio_recorder.dart';
import 'stt_engine.dart';

class MockSttEngine implements SttEngine {
  bool _ready = false;

  @override
  Future<bool> isReady() async => _ready;

  @override
  Future<void> prepare() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _ready = true;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    throw StateError(
      'No local speech runtime is configured. Set up Whisper before dictating.',
    );
  }
}
