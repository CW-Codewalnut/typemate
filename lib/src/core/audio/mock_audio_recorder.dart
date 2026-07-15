import 'audio_recorder.dart';

class MockAudioRecorder implements AudioRecorder {
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  @override
  Future<void> start() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _isRecording = true;
  }

  @override
  Future<AudioRecording> stop() async {
    if (!_isRecording) {
      return const AudioRecording(
        path: 'mock-empty.wav',
        duration: Duration.zero,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
    _isRecording = false;

    return const AudioRecording(
      path: 'mock-latest-dictation.wav',
      duration: Duration(milliseconds: 1200),
    );
  }
}
