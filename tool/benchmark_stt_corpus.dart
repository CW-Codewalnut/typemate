import 'dart:convert';
import 'dart:io';

import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';

/// Runs a whisper GGML model over the benchmark corpus for one language and
/// prints expected vs actual transcripts with latency, so model choices are
/// compared against the same clips every time.
///
/// Usage:
///   dart run tool/benchmark_stt_corpus.dart --model `<path.bin>`
///     --language hi [--cli-language hi]
Future<void> main(List<String> arguments) async {
  final modelPath = _valueAfter(arguments, '--model');
  final language = _valueAfter(arguments, '--language');
  if (modelPath == null || language == null) {
    stderr.writeln(
      'Usage: dart run tool/benchmark_stt_corpus.dart '
      '--model <path.bin> --language <code> [--cli-language <code>]',
    );
    exitCode = 64;
    return;
  }
  final cliLanguage = _valueAfter(arguments, '--cli-language') ?? language;

  final manifest =
      jsonDecode(
            File('test_assets/stt_benchmark/manifest.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final clips = (manifest['clips'] as List)
      .cast<Map<String, dynamic>>()
      .where((clip) => clip['language'] == language)
      .toList();
  if (clips.isEmpty) {
    stderr.writeln('No corpus clips for language "$language".');
    exitCode = 65;
    return;
  }

  final engine = WhisperCliSttEngine(
    executable: 'bin/whisper/whisper-cli${Platform.isWindows ? '.exe' : ''}',
    modelPath: modelPath,
    vadModelPath: 'models/ggml-silero-v5.1.2.bin',
    languageCodeProvider: () => cliLanguage,
  );

  for (final clip in clips) {
    final file = clip['file'] as String;
    final path = 'test_assets/stt_benchmark/$file';
    final stopwatch = Stopwatch()..start();
    final transcript = await engine.transcribe(
      AudioRecording(path: path, duration: Duration.zero),
    );
    stopwatch.stop();
    stdout
      ..writeln('clip: $file (${stopwatch.elapsedMilliseconds}ms)')
      ..writeln('  expected: ${clip['expected']}')
      ..writeln('  actual:   $transcript');
  }
}

String? _valueAfter(List<String> arguments, String flag) {
  final index = arguments.indexOf(flag);
  if (index == -1 || index + 1 >= arguments.length) {
    return null;
  }
  return arguments[index + 1];
}
