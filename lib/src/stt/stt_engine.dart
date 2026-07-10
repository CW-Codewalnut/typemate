abstract interface class SttEngine {
  Future<bool> isReady();

  Future<void> prepare();

  Future<String> transcribeLatestRecording();
}
