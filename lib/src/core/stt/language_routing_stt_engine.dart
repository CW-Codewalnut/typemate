import '../audio/audio_recorder.dart';
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart';

/// Routes each transcription to the engine registered for the selected
/// language, falling back to [fallback] for everything else. This lets
/// English run on the resident Parakeet server while Hindi and Hinglish
/// stay on the whisper CLI.
class LanguageRoutingSttEngine implements DisposableSttEngine {
  LanguageRoutingSttEngine({
    required this.routes,
    required this.fallback,
    required this.languageCodeProvider,
  });

  final Map<String, SttEngine> routes;
  final SttEngine fallback;
  final SttLanguageCodeProvider languageCodeProvider;

  Iterable<SttEngine> get _allEngines => [...routes.values, fallback];

  SttEngine get _currentEngine =>
      routes[languageCodeProvider().trim().toLowerCase()] ?? fallback;

  @override
  Future<bool> isReady() async {
    for (final engine in _allEngines) {
      if (!await engine.isReady()) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> prepare() async {
    for (final engine in _allEngines) {
      await engine.prepare();
    }
  }

  @override
  Future<String> transcribe(AudioRecording recording) =>
      _currentEngine.transcribe(recording);

  @override
  Future<void> shutdown() async {
    for (final engine in _allEngines) {
      if (engine is DisposableSttEngine) {
        await engine.shutdown();
      }
    }
  }
}
