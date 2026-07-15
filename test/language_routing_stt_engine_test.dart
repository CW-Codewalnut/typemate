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
      final english = RecordingSttEngine('english transcript');
      final fallback = RecordingSttEngine('fallback transcript');
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

      language = 'hinglish';
      expect(await engine.transcribe(recording), 'fallback transcript');
      expect(fallback.transcribeCalls, 2);
    },
  );

  test(
    'prepare readies every engine so the server starts at app open',
    () async {
      final english = RecordingSttEngine('a');
      final fallback = RecordingSttEngine('b');
      final engine = LanguageRoutingSttEngine(
        routes: {'en': english},
        fallback: fallback,
        languageCodeProvider: () => 'en',
      );

      await engine.prepare();

      expect(english.prepareCalls, 1);
      expect(fallback.prepareCalls, 1);
    },
  );

  test('isReady is false when any engine is not ready', () async {
    final english = RecordingSttEngine('a')..ready = false;
    final fallback = RecordingSttEngine('b');
    final engine = LanguageRoutingSttEngine(
      routes: {'en': english},
      fallback: fallback,
      languageCodeProvider: () => 'en',
    );

    expect(await engine.isReady(), isFalse);
    english.ready = true;
    expect(await engine.isReady(), isTrue);
  });

  test('shutdown reaches disposable engines only', () async {
    final english = DisposableRecordingSttEngine('a');
    final fallback = RecordingSttEngine('b');
    final engine = LanguageRoutingSttEngine(
      routes: {'en': english},
      fallback: fallback,
      languageCodeProvider: () => 'en',
    );

    await engine.shutdown();

    expect(english.shutdownCalls, 1);
  });
}

class RecordingSttEngine implements SttEngine {
  RecordingSttEngine(this.transcript);

  final String transcript;
  bool ready = true;
  int prepareCalls = 0;
  int transcribeCalls = 0;

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
}

class DisposableRecordingSttEngine extends RecordingSttEngine
    implements DisposableSttEngine {
  DisposableRecordingSttEngine(super.transcript);

  int shutdownCalls = 0;

  @override
  Future<void> shutdown() async {
    shutdownCalls += 1;
  }
}
