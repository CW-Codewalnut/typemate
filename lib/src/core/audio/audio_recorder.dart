class AudioRecording {
  const AudioRecording({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

abstract interface class AudioRecorder {
  Future<void> start();

  Future<AudioRecording> stop();
}
