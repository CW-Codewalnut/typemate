import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/language_routing_stt_engine.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';

void main() {
  const recording = AudioRecording(
    path: 'clip.wav',
    duration: Duration(seconds: 2),
  );

  test(
    'routes transcription to the engine for the selected language',
    () async {
      final english = DisposableRecordingSttEngine('english transcript');
      final fallback = DisposableRecordingSttEngine('fallback transcript');
      var language = 'en';
      final engine = LanguageRoutingSttEngine(
        routes: {'en': english},
        fallback: fallback,
        languageCodeProvider: () => language,
      );

      expect(await engine.transcribe(recording), 'english transcript');
      expect(english.transcribeCalls, 1);
      expect(fallback.transcribeCalls, 0);

      language = 'hi';
      expect(await engine.transcribe(recording), 'fallback transcript');
      expect(fallback.transcribeCalls, 1);
    },
  );

  test('keeps only the selected language engine warm to save RAM', () async {
    final english = DisposableRecordingSttEngine('a');
    final hindi = DisposableRecordingSttEngine('b');
    var language = 'en';
    final engine = LanguageRoutingSttEngine(
      routes: {'en': english, 'hi': hindi},
      fallback: hindi,
      languageCodeProvider: () => language,
    );

    // Preparing English shuts the Hindi server down, not English.
    await engine.prepare();
    expect(english.prepareCalls, 1);
    expect(english.shutdownCalls, 0);
    expect(hindi.shutdownCalls, 1);

    // Switching to Hindi and preparing shuts English down.
    language = 'hi';
    await engine.prepare();
    expect(hindi.prepareCalls, 1);
    expect(english.shutdownCalls, 1);

    // Transcribing also enforces the single-active-engine rule.
    language = 'en';
    await engine.transcribe(recording);
    expect(hindi.shutdownCalls, 2);
    expect(english.transcribeCalls, 1);
  });

  test('isReady reflects the active engine only', () async {
    final english = DisposableRecordingSttEngine('a')..ready = false;
    final hindi = DisposableRecordingSttEngine('b');
    var language = 'hi';
    final engine = LanguageRoutingSttEngine(
      routes: {'en': english, 'hi': hindi},
      fallback: hindi,
      languageCodeProvider: () => language,
    );

    expect(await engine.isReady(), isTrue);
    language = 'en';
    expect(await engine.isReady(), isFalse);
  });

  test('shutdown reaches every disposable engine', () async {
    final english = DisposableRecordingSttEngine('a');
    final hindi = DisposableRecordingSttEngine('b');
    final engine = LanguageRoutingSttEngine(
      routes: {'en': english, 'hi': hindi},
      fallback: hindi,
      languageCodeProvider: () => 'en',
    );

    await engine.shutdown();

    expect(english.shutdownCalls, 1);
    expect(hindi.shutdownCalls, 1);
  });
}

class DisposableRecordingSttEngine implements DisposableSttEngine {
  DisposableRecordingSttEngine(this.transcript);

  final String transcript;
  bool ready = true;
  int prepareCalls = 0;
  int transcribeCalls = 0;
  int shutdownCalls = 0;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<void> prepare() async {
    prepareCalls += 1;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    transcribeCalls += 1;
    return transcript;
  }

  @override
  Future<void> shutdown() async {
    shutdownCalls += 1;
  }
}
