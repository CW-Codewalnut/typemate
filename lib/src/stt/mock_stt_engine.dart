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
  Future<String> transcribeLatestRecording() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return 'This is a local dictation preview. The production build will insert the real transcript here.';
  }
}
