import '../audio/audio_recorder.dart';
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart';

/// Routes each transcription to the engine registered for the selected
/// language, falling back to [fallback] for everything else.
///
/// Only the selected language's engine is kept warm: preparing or using a
/// language shuts every other disposable engine down first, so a single
/// resident model server occupies RAM at a time.
class LanguageRoutingSttEngine implements DisposableSttEngine {
  LanguageRoutingSttEngine({
    required this.routes,
    required this.fallback,
    required this.languageCodeProvider,
  });

  final Map<String, SttEngine> routes;
  final SttEngine fallback;
  final SttLanguageCodeProvider languageCodeProvider;

  Iterable<SttEngine> get _allEngines => {...routes.values, fallback};

  SttEngine get _activeEngine =>
      routes[languageCodeProvider().trim().toLowerCase()] ?? fallback;

  Future<SttEngine> _syncToActiveEngine() async {
    final active = _activeEngine;
    for (final engine in _allEngines) {
      if (!identical(engine, active) && engine is DisposableSttEngine) {
        await engine.shutdown();
      }
    }
    return active;
  }

  @override
  Future<bool> isReady() async {
    final active = await _syncToActiveEngine();
    return active.isReady();
  }

  @override
  Future<void> prepare() async {
    final active = await _syncToActiveEngine();
    await active.prepare();
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    final active = await _syncToActiveEngine();
    return active.transcribe(recording);
  }

  @override
  Future<void> shutdown() async {
    for (final engine in _allEngines) {
      if (engine is DisposableSttEngine) {
        await engine.shutdown();
      }
    }
  }
}
