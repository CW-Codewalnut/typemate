// Proves real Hindi/Hinglish/Tamil transcription through the production
// WhisperGgmlSttEngine (resident model + Silero VAD via the patched
// whisper_ggml fork) against the persistent benchmark corpus, three runs
// per language for repeat-request stability.
//
// Usage (pure Dart; needs the plugin DLL on PATH, e.g. the app build dir):
//   PATH="build/windows/x64/runner/Debug:$PATH" \
//     dart run tool/benchmark_whisper_ggml_engine.dart
import 'dart:convert';
import 'dart:io';

import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_ggml_stt_engine.dart';

const _corpusDirectory = 'test_assets/stt_benchmark';

Future<void> main() async {
  final root = Directory.current.path.replaceAll('\\', '/');
  final manifest =
      jsonDecode(
            File(
              '$_corpusDirectory/manifest.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map<String, dynamic>;
  final clips = (manifest['clips'] as List).cast<Map<String, dynamic>>();

  final languages = [
    (
      label: 'hindi',
      model: 'ggml-small-vaani-hindi-q6.bin',
      language: 'hi',
      prompt: null,
      clip: 'hi-market.wav',
    ),
    (
      label: 'hindi-noisy',
      model: 'ggml-small-vaani-hindi-q6.bin',
      language: 'hi',
      prompt: null,
      clip: 'hi-market-noisy.wav',
    ),
    (
      label: 'hinglish',
      model: 'ggml-hindi2hinglish-swift.bin',
      language: 'hi',
      prompt: null,
      clip: 'hi-market.wav',
    ),
    (
      label: 'tamil',
      model: 'ggml-vistaar-tamil-small-q5_0.bin',
      language: 'ta',
      prompt: null,
      clip: 'ta-market.wav',
    ),
  ];

  for (final entry in languages) {
    final engine = WhisperGgmlSttEngine(
      modelPath: '$root/models/${entry.model}',
      language: entry.language,
      vadModelPath: '$root/models/ggml-silero-v5.1.2.bin',
      prompt: entry.prompt,
    );
    final prepareStopwatch = Stopwatch()..start();
    await engine.prepare();
    stdout.writeln(
      'ENGINE|${entry.label}|prepare_ms=${prepareStopwatch.elapsedMilliseconds}',
    );
    final expected = clips.firstWhere(
      (c) => c['file'] == entry.clip,
    )['expected'];
    for (var i = 0; i < 3; i++) {
      final stopwatch = Stopwatch()..start();
      final text = await engine.transcribe(
        AudioRecording(
          path: '$_corpusDirectory/${entry.clip}',
          duration: const Duration(seconds: 13),
        ),
      );
      stdout
        ..writeln(
          'ENGINE|${entry.label}|run$i|ms=${stopwatch.elapsedMilliseconds}',
        )
        ..writeln('  expected: $expected')
        ..writeln('  got:      $text');
    }
    await engine.shutdown();
  }
}
