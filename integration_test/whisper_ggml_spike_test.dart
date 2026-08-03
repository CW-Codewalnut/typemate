import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Spike: our whisper fine-tunes through the whisper_ggml plugin (vendored
/// whisper.cpp v1.9.1, AVX2 baseline) — quality, latency, and
/// repeat-request stability, printed for comparison against the resident
/// whisper-server numbers. Not a pass/fail gate yet: this drives the
/// adopt/no-adopt decision for replacing bin/whisper.
///
/// Run: flutter test integration_test/whisper_ggml_spike_test.dart -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const hindiPrompt =
      'हिंदी भाषण को देवनागरी लिपि में ठीक-ठीक लिखें। '
      'अंग्रेज़ी में अनुवाद न करें।';

  testWidgets(
    'fine-tunes through whisper_ggml',
    (tester) async {
      final root = Directory.current.path.replaceAll('\\', '/');
      final temp = Directory.systemTemp.createTempSync('typemate-ggml-spike');
      addTearDown(() => temp.deleteSync(recursive: true));

      String stage(String corpusFile) {
        final staged = '${temp.path}/$corpusFile';
        File('$root/test_assets/stt_benchmark/$corpusFile').copySync(staged);
        return staged;
      }

      Future<void> run({
        required String label,
        required String model,
        required String clip,
        required String lang,
        String? prompt,
      }) async {
        final whisper = Whisper(model: WhisperModel.tiny);
        final modelPath = '$root/models/$model';
        for (var i = 0; i < 3; i++) {
          final stopwatch = Stopwatch()..start();
          final response = await whisper.transcribe(
            transcribeRequest: TranscribeRequest(
              audio: clip,
              language: lang,
              isNoTimestamps: true,
              threads: 6,
              initialPrompt: prompt,
              // Short single utterances: prior-segment context only invites
              // repetition (same reasoning as the server path's VAD trim).
              noContext: true,
            ),
            modelPath: modelPath,
          );
          // ignore: avoid_print
          print(
            'SPIKE|$label|run$i|ms=${stopwatch.elapsedMilliseconds}'
            '|text=${response.text.trim()}',
          );
        }
      }

      final hindiClip = stage('hi-market.wav');
      final hindiNoisyClip = stage('hi-market-noisy.wav');
      final tamilClip = stage('ta-market.wav');

      await run(
        label: 'hindi',
        model: 'ggml-small-vaani-hindi-q6.bin',
        clip: hindiClip,
        lang: 'hi',
        prompt: hindiPrompt,
      );
      await run(
        label: 'hindi-noisy',
        model: 'ggml-small-vaani-hindi-q6.bin',
        clip: hindiNoisyClip,
        lang: 'hi',
        prompt: hindiPrompt,
      );
      await run(
        label: 'hinglish',
        model: 'ggml-hindi2hinglish-swift.bin',
        clip: hindiClip,
        lang: 'hi',
      );
      await run(
        label: 'tamil',
        model: 'ggml-vistaar-tamil-small-q5_0.bin',
        clip: tamilClip,
        lang: 'ta',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
