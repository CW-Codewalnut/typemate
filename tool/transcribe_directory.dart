// Transcribes WAVs through an in-process STT engine, so real-world
// recordings can be checked against candidate models without running the
// app. Defaults to the exact model files and recognizer config
// SherpaParakeetSttEngine loads.
//
// Usage (pure Dart, no Flutter runtime needed):
//   dart run tool/transcribe_directory.dart <wav-dir> \
//     [--model-dir models/parakeet-unified-en-0.6b-int8] \
//     [--type transducer|whisper|canary|moonshine|qwen3-asr|nemo-ctc] \
//     [--lib-dir <dll dir>]
//
// With --manifest it scores WER against the reference transcripts instead
// of just printing text (see test_assets/stt_benchmark/manifest.json):
//   dart run tool/transcribe_directory.dart \
//     --manifest test_assets/stt_benchmark/manifest.json \
//     --language en [--dialect en-IN] --type <type> --model-dir <dir>
//
// Or through the production whisper_ggml engine. That needs the plugin
// DLL on PATH, and it MUST be the Release copy — the Debug DLLs mix CRT
// heaps with the release Dart VM and abort the process with
// 0xC0000374 (STATUS_HEAP_CORRUPTION) right after the warm-up VAD call,
// printing nothing at all:
//   PATH="build/windows/x64/runner/Release:$PATH" \
//     dart run tool/transcribe_directory.dart <wav-dir> \
//     --engine whisper-ggml --model models/ggml-small-vaani-hindi-q6.bin \
//     --language hi
// --model takes a single .bin there, where sherpa's --model-dir takes a
// directory; both accept --manifest.
//
// sherpa model files are located inside --model-dir by the standard names
// used in the k2-fsa/sherpa-onnx release archives, preferring int8 variants.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/wave_audio_guard.dart';
import 'package:typemate/src/core/stt/whisper_ggml_stt_engine.dart';

/// The sherpa_onnx_windows copy THIS project resolved, read from the
/// package config rather than guessed from the shared pub cache: the
/// cache can hold several versions, and loading the wrong one brings back
/// the ORT API mismatch this exists to avoid. Pass --lib-dir to override.
String _defaultLibraryDirectory() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    return '';
  }
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final root =
      packages.cast<Map<String, dynamic>>().firstWhere(
            (p) => p['name'] == 'sherpa_onnx_windows',
            orElse: () => const <String, dynamic>{},
          )['rootUri']
          as String?;
  if (root == null) {
    return '';
  }
  final resolved = Uri.parse(root).toFilePath().replaceAll('\\', '/');
  return '$resolved/windows';
}

/// Finds the model file in [directory] whose name contains [nameFragment],
/// preferring int8 exports to match what the app would ship.
String _find(String directory, String nameFragment) {
  final candidates =
      Directory(directory)
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/'))
          .where((p) => p.split('/').last.contains(nameFragment))
          .toList()
        ..sort();
  if (candidates.isEmpty) {
    throw StateError('No "$nameFragment" file in $directory');
  }
  return candidates.firstWhere(
    (p) => p.contains('int8'),
    orElse: () => candidates.first,
  );
}

sherpa_onnx.OfflineModelConfig _modelConfig(
  String type,
  String directory,
  String language,
) {
  if (type == 'qwen3-asr') {
    // Qwen3-ASR ships a tokenizer directory instead of a tokens.txt.
    return sherpa_onnx.OfflineModelConfig(
      qwen3Asr: sherpa_onnx.OfflineQwen3AsrModelConfig(
        convFrontend: _find(directory, 'conv_frontend'),
        encoder: _find(directory, 'encoder'),
        decoder: _find(directory, 'decoder'),
        tokenizer: '$directory/tokenizer',
      ),
      tokens: '',
      numThreads: 4,
    );
  }
  final tokens = _find(directory, 'tokens');
  switch (type) {
    case 'transducer':
      return sherpa_onnx.OfflineModelConfig(
        transducer: sherpa_onnx.OfflineTransducerModelConfig(
          encoder: _find(directory, 'encoder'),
          decoder: _find(directory, 'decoder'),
          joiner: _find(directory, 'joiner'),
        ),
        tokens: tokens,
        modelType: 'nemo_transducer',
        numThreads: 4,
      );
    case 'moonshine':
      return sherpa_onnx.OfflineModelConfig(
        moonshine: sherpa_onnx.OfflineMoonshineModelConfig(
          preprocessor: _find(directory, 'preprocess'),
          encoder: _find(directory, 'encode'),
          uncachedDecoder: _find(directory, 'uncached_decode'),
          cachedDecoder: _find(directory, 'cached_decode'),
        ),
        tokens: tokens,
        numThreads: 4,
      );
    case 'whisper':
      return sherpa_onnx.OfflineModelConfig(
        whisper: sherpa_onnx.OfflineWhisperModelConfig(
          encoder: _find(directory, 'encoder'),
          decoder: _find(directory, 'decoder'),
          // Multilingual whisper exports decode whatever language they are
          // told to; forcing 'en' on non-English audio measures nothing.
          language: language,
          task: 'transcribe',
        ),
        tokens: tokens,
        numThreads: 4,
      );
    case 'canary':
      return sherpa_onnx.OfflineModelConfig(
        canary: sherpa_onnx.OfflineCanaryModelConfig(
          encoder: _find(directory, 'encoder'),
          decoder: _find(directory, 'decoder'),
        ),
        tokens: tokens,
        numThreads: 4,
      );
    case 'nemo-ctc':
      return sherpa_onnx.OfflineModelConfig(
        nemoCtc: sherpa_onnx.OfflineNemoEncDecCtcModelConfig(
          model: _find(directory, 'model'),
        ),
        tokens: tokens,
        numThreads: 4,
      );
    default:
      throw ArgumentError('Unknown --type "$type"');
  }
}

/// One loaded engine: transcribe a WAV, then release it. Both engines
/// expose this, so the manifest and directory runners are written once —
/// the duplicated pair of runners is what let --manifest work on sherpa
/// and silently do nothing on whisper_ggml.
class _Engine {
  const _Engine({required this.transcribe, required this.close});

  final Future<String> Function(String wavPath) transcribe;
  final Future<void> Function() close;
}

_Engine _sherpaEngine({
  required String type,
  required String modelDirectory,
  required String language,
  required String libraryDirectory,
}) {
  final normalized = libraryDirectory.replaceAll('/', '\\');
  if (normalized.isNotEmpty) {
    // Pre-pin the bundled onnxruntime BEFORE sherpa loads: Windows ML
    // ships an older onnxruntime.dll in System32, which otherwise wins
    // the dependency search and crashes with an ORT API mismatch. (The
    // real app is immune — its own copy sits next to typemate.exe.)
    DynamicLibrary.open('$normalized\\onnxruntime.dll');
  }
  sherpa_onnx.initBindings(normalized.isEmpty ? null : normalized);

  final stopwatch = Stopwatch()..start();
  final recognizer = sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(
      model: _modelConfig(type, modelDirectory, language),
    ),
  );
  stdout.writeln('model_loaded_ms=${stopwatch.elapsedMilliseconds}');

  return _Engine(
    transcribe: (wavPath) async {
      final wave = sherpa_onnx.readWave(wavPath);
      // Degenerate audio aborts the process inside sherpa's native code,
      // the same way it does in the app engine; a corpus clip that failed
      // to convert should report itself, not kill the run. Checks the
      // sample RATE too: an unreadable file is the case that actually
      // crashes, and checking only for zero samples missed it.
      if (waveAudioRefusal(
            sampleCount: wave.samples.length,
            sampleRate: wave.sampleRate,
          ) !=
          null) {
        return '';
      }
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();
      return text;
    },
    close: () async => recognizer.free(),
  );
}

Future<_Engine> _whisperGgmlEngine({
  required String modelPath,
  required String language,
}) async {
  final engine = WhisperGgmlSttEngine(
    modelPath: modelPath,
    language: language,
    vadModelPath: 'models/ggml-silero-v5.1.2.bin',
  );
  final stopwatch = Stopwatch()..start();
  await engine.prepare();
  stdout.writeln('model_loaded_ms=${stopwatch.elapsedMilliseconds}');
  return _Engine(
    transcribe: (wavPath) => engine.transcribe(
      AudioRecording(path: wavPath, duration: Duration.zero),
    ),
    close: engine.shutdown,
  );
}

/// Seconds of audio in a PCM WAV, from its header — engine-agnostic, so
/// both runners can report it.
double _wavSeconds(File file) {
  final header = file.openSync()..setPositionSync(0);
  try {
    final bytes = ByteData.sublistView(header.readSync(44));
    final channels = bytes.getUint16(22, Endian.little);
    final sampleRate = bytes.getUint32(24, Endian.little);
    final bitsPerSample = bytes.getUint16(34, Endian.little);
    final bytesPerFrame = channels * (bitsPerSample ~/ 8);
    if (sampleRate == 0 || bytesPerFrame == 0) {
      return 0;
    }
    return (file.lengthSync() - 44) / (sampleRate * bytesPerFrame);
  } finally {
    header.closeSync();
  }
}

/// Lowercases, strips punctuation, and splits into words so WER measures
/// recognition quality rather than formatting differences. Keeps letters
/// and digits in EVERY script: a Latin-only class silently normalized
/// Devanagari and Tamil references to nothing, turning their WER into
/// Infinity% instead of a number.
List<String> _normalizedWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"[^\p{L}\p{N}']+", unicode: true), ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Word-level Levenshtein distance (substitutions + insertions + deletions).
int _editDistance(List<String> reference, List<String> hypothesis) {
  final previous = List<int>.generate(hypothesis.length + 1, (i) => i);
  final current = List<int>.filled(hypothesis.length + 1, 0);
  for (var i = 1; i <= reference.length; i++) {
    current[0] = i;
    for (var j = 1; j <= hypothesis.length; j++) {
      final substitution =
          previous[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1);
      current[j] = math.min(
        substitution,
        math.min(previous[j] + 1, current[j - 1] + 1),
      );
    }
    previous.setAll(0, current);
  }
  return previous[hypothesis.length];
}

Future<void> _runManifest(
  _Engine engine,
  String manifestPath,
  String language,
  String dialectFilter,
) async {
  final manifestFile = File(manifestPath);
  final manifestDirectory = manifestFile.parent.path.replaceAll('\\', '/');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync(encoding: utf8))
          as Map<String, dynamic>;
  final clips = (manifest['clips'] as List)
      .cast<Map<String, dynamic>>()
      .where((c) => c['language'] == language)
      .where(
        (c) =>
            dialectFilter.isEmpty ||
            (c['dialect'] as String? ?? '').contains(dialectFilter),
      )
      .toList();
  if (clips.isEmpty) {
    stderr.writeln('No manifest clips match language "$language".');
    exitCode = 65;
    return;
  }

  final errorsByDialect = <String, int>{};
  final wordsByDialect = <String, int>{};
  var missingAudio = 0;
  var missingReference = 0;
  for (final clip in clips) {
    final wavPath = '$manifestDirectory/${clip['file']}';
    if (!File(wavPath).existsSync()) {
      stderr.writeln('SKIPPED (audio missing): ${clip['file']}');
      missingAudio++;
      continue;
    }
    // Clips with no reference (or one that normalizes to nothing) cannot
    // be scored. Counting them out loud matters: they used to vanish in a
    // filter, so a run over 10 clips could report a number from 2 and
    // still read like full coverage.
    final reference = _normalizedWords(clip['expected'] as String? ?? '');
    if (reference.isEmpty) {
      stderr.writeln('SKIPPED (no reference transcript): ${clip['file']}');
      missingReference++;
      continue;
    }
    final decodeStopwatch = Stopwatch()..start();
    final text = await engine.transcribe(wavPath);
    final errors = _editDistance(reference, _normalizedWords(text));
    final dialect = clip['dialect'] as String? ?? 'unknown';
    errorsByDialect[dialect] = (errorsByDialect[dialect] ?? 0) + errors;
    wordsByDialect[dialect] = (wordsByDialect[dialect] ?? 0) + reference.length;
    final wer = (100 * errors / reference.length).toStringAsFixed(1);
    final verified = clip['verified'] == true ? '' : ' (unverified reference)';
    stdout
      ..writeln(
        'clip=${clip['file']} dialect=$dialect '
        'decode_ms=${decodeStopwatch.elapsedMilliseconds} '
        'wer=$wer%$verified',
      )
      ..writeln('  expected: ${clip['expected']}')
      ..writeln('  got:      $text');
  }

  final scored = clips.length - missingAudio - missingReference;
  if (wordsByDialect.isEmpty) {
    stderr.writeln(
      'No clip was scored for "$language": $missingAudio missing audio, '
      '$missingReference without a reference transcript.',
    );
    exitCode = 66;
    return;
  }

  stdout.writeln('--- WER by dialect ---');
  var totalErrors = 0;
  var totalWords = 0;
  for (final dialect in errorsByDialect.keys.toList()..sort()) {
    final errors = errorsByDialect[dialect]!;
    final words = wordsByDialect[dialect]!;
    totalErrors += errors;
    totalWords += words;
    stdout.writeln(
      '$dialect: ${(100 * errors / words).toStringAsFixed(1)}% '
      '($errors/$words words)',
    );
  }
  stdout.writeln(
    'overall: ${(100 * totalErrors / totalWords).toStringAsFixed(1)}% '
    '($totalErrors/$totalWords words)',
  );
  // The headline is only as broad as the clips behind it.
  stdout.writeln(
    'scored $scored of ${clips.length} clips '
    '($missingAudio missing audio, $missingReference without a reference)',
  );
}

Future<void> _runDirectories(_Engine engine, List<String> directories) async {
  for (final directory in directories) {
    final wavFiles =
        Directory(directory)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final wavFile in wavFiles) {
      final decodeStopwatch = Stopwatch()..start();
      final text = await engine.transcribe(wavFile.path);
      stdout
        ..writeln(
          'clip=${wavFile.uri.pathSegments.last} '
          'audio_s=${_wavSeconds(wavFile).toStringAsFixed(1)} '
          'decode_ms=${decodeStopwatch.elapsedMilliseconds}',
        )
        ..writeln('  $text');
    }
  }
}

Future<void> main(List<String> arguments) async {
  final directories = <String>[];
  var modelDirectory = 'models/parakeet-unified-en-0.6b-int8';
  var libraryDirectory = _defaultLibraryDirectory();
  var type = 'transducer';
  var engineName = 'sherpa';
  var language = 'en';
  var manifestPath = '';
  var dialectFilter = '';
  for (var i = 0; i < arguments.length; i++) {
    final flag = arguments[i];
    if (!flag.startsWith('--')) {
      directories.add(flag);
      continue;
    }
    // A trailing flag with no value is a typo, not a crash.
    if (i + 1 >= arguments.length) {
      stderr.writeln('Missing value after $flag.');
      exitCode = 64;
      return;
    }
    final argument = arguments[++i];
    switch (flag) {
      // --model is the whisper-ggml spelling (a single .bin file);
      // --model-dir the sherpa one (a directory of ONNX files). Same
      // slot, because only one engine runs per invocation.
      case '--model-dir':
      case '--model':
        modelDirectory = argument;
      case '--lib-dir':
        libraryDirectory = argument;
      case '--type':
        type = argument;
      case '--engine':
        engineName = argument;
      case '--language':
        language = argument;
      case '--manifest':
        manifestPath = argument;
      case '--dialect':
        dialectFilter = argument;
      default:
        stderr.writeln('Unknown flag $flag.');
        exitCode = 64;
        return;
    }
  }
  if (directories.isEmpty && manifestPath.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/transcribe_directory.dart <wav-dir> '
      '| --manifest <manifest.json>',
    );
    exitCode = 64;
    return;
  }

  final engine = engineName == 'whisper-ggml'
      ? await _whisperGgmlEngine(modelPath: modelDirectory, language: language)
      : _sherpaEngine(
          type: type,
          modelDirectory: modelDirectory,
          language: language,
          libraryDirectory: libraryDirectory,
        );
  try {
    if (manifestPath.isNotEmpty) {
      await _runManifest(engine, manifestPath, language, dialectFilter);
    } else {
      await _runDirectories(engine, directories);
    }
  } finally {
    await engine.close();
  }
}
