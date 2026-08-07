// Transcribes every WAV in a directory through an in-process STT engine,
// so real-world recordings can be checked against candidate models without
// running the app. Defaults to the exact model files and recognizer config
// SherpaParakeetSttEngine loads.
//
// Usage (pure Dart, no Flutter runtime needed):
//   dart run tool/transcribe_directory.dart <wav-dir> \
//     [--model-dir models/parakeet-tdt-0.6b-v3-int8] \
//     [--type transducer|moonshine|whisper|canary|zipformer-ctc|sense-voice] \
//     [--lib-dir <dll dir>]
//
// With --manifest it scores WER against the reference transcripts instead
// of just printing text (see test_assets/stt_benchmark/manifest.json):
//   dart run tool/transcribe_directory.dart \
//     --manifest test_assets/stt_benchmark/manifest.json \
//     --language en [--dialect en-IN] --type <type> --model-dir <dir>
//
// Or through the production whisper_ggml engine (needs the plugin DLL on
// PATH, e.g. build/windows/x64/runner/Debug). --model takes a single
// .bin here, where sherpa's --model-dir takes a directory; both accept
// --manifest for WER scoring:
//   dart run tool/transcribe_directory.dart <wav-dir> \
//     --engine whisper-ggml --model models/ggml-small-vaani-hindi-q6.bin \
//     --language hi
//
// sherpa model files are located inside --model-dir by the standard names
// used in the k2-fsa/sherpa-onnx release archives, preferring int8 variants.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_ggml_stt_engine.dart';

/// The newest sherpa_onnx_windows in the pub cache, so a plugin bump does
/// not silently drop the tool back to the System32 onnxruntime (which
/// crashes with an ORT API mismatch). Pass --lib-dir to override.
String _defaultLibraryDirectory() {
  final home = Platform.environment['USERPROFILE'] ?? '';
  final hosted = Directory('$home/AppData/Local/Pub/Cache/hosted/pub.dev');
  if (!hosted.existsSync()) {
    return '';
  }
  final versions =
      hosted
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.replaceAll('\\', '/'))
          .where((p) => p.split('/').last.startsWith('sherpa_onnx_windows-'))
          .toList()
        ..sort();
  if (versions.isEmpty) {
    return '';
  }
  final windows = '${versions.last}/windows';
  return Directory(windows).existsSync() ? windows : '';
}

/// Finds the model file in [directory] whose name contains [nameFragment],
/// preferring int8 exports to match what the app would ship.
String _find(String directory, String nameFragment, {bool optional = false}) {
  final candidates =
      Directory(directory)
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/'))
          .where((p) => p.split('/').last.contains(nameFragment))
          .toList()
        ..sort();
  if (candidates.isEmpty) {
    if (optional) {
      return '';
    }
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
    case 'zipformer-ctc':
      return sherpa_onnx.OfflineModelConfig(
        zipformerCtc: sherpa_onnx.OfflineZipformerCtcModelConfig(
          model: _find(directory, 'model'),
        ),
        tokens: tokens,
        numThreads: 4,
      );
    case 'sense-voice':
      return sherpa_onnx.OfflineModelConfig(
        senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
          model: _find(directory, 'model'),
          language: 'en',
        ),
        tokens: tokens,
        numThreads: 4,
      );
    default:
      throw ArgumentError('Unknown --type "$type"');
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

/// Transcribes one WAV; lets the manifest scorer drive any engine.
typedef ClipTranscriber = Future<String> Function(String wavPath);

/// Word-level Levenshtein distance (substitutions + insertions + deletions).
int _editDistance(List<String> reference, List<String> hypothesis) {
  final previous = List<int>.generate(hypothesis.length + 1, (i) => i);
  final current = List<int>.filled(hypothesis.length + 1, 0);
  for (var i = 1; i <= reference.length; i++) {
    current[0] = i;
    for (var j = 1; j <= hypothesis.length; j++) {
      final substitution =
          previous[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1);
      current[j] = [
        substitution,
        previous[j] + 1,
        current[j - 1] + 1,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous.setAll(0, current);
  }
  return previous[hypothesis.length];
}

Future<void> _runManifest(
  ClipTranscriber transcribe,
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
      .where((c) => (c['expected'] as String? ?? '').isNotEmpty)
      .toList();
  if (clips.isEmpty) {
    stderr.writeln('No manifest clips match language "$language".');
    exitCode = 65;
    return;
  }

  final errorsByDialect = <String, int>{};
  final wordsByDialect = <String, int>{};
  for (final clip in clips) {
    final wavPath = '$manifestDirectory/${clip['file']}';
    if (!File(wavPath).existsSync()) {
      stderr.writeln('SKIPPED (file missing): ${clip['file']}');
      continue;
    }
    final reference = _normalizedWords(clip['expected'] as String);
    if (reference.isEmpty) {
      stderr.writeln(
        'SKIPPED (reference normalizes to no words): '
        '${clip['file']}',
      );
      continue;
    }
    final decodeStopwatch = Stopwatch()..start();
    final text = await transcribe(wavPath);
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

  if (wordsByDialect.isEmpty) {
    // Every clip was skipped — missing audio (a fresh clone has only the
    // committed synthetic clips) or references that normalize to nothing.
    // Saying so beats printing NaN% and looking like a score.
    stderr.writeln('No clip was scored: no audio present for "$language".');
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
}

List<File> _wavFiles(String directory) =>
    Directory(directory)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.wav'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

Future<void> _runWhisperGgml(
  List<String> directories,
  String modelPath,
  String language,
  String manifestPath,
  String dialectFilter,
) async {
  final engine = WhisperGgmlSttEngine(
    modelPath: modelPath,
    language: language,
    vadModelPath: 'models/ggml-silero-v5.1.2.bin',
  );
  final prepareStopwatch = Stopwatch()..start();
  await engine.prepare();
  stdout.writeln('model_loaded_ms=${prepareStopwatch.elapsedMilliseconds}');
  if (manifestPath.isNotEmpty) {
    await _runManifest(
      (wavPath) => engine.transcribe(
        AudioRecording(path: wavPath, duration: Duration.zero),
      ),
      manifestPath,
      language,
      dialectFilter,
    );
    await engine.shutdown();
    return;
  }
  for (final directory in directories) {
    for (final wavFile in _wavFiles(directory)) {
      final decodeStopwatch = Stopwatch()..start();
      final text = await engine.transcribe(
        AudioRecording(path: wavFile.path, duration: Duration.zero),
      );
      stdout
        ..writeln(
          'clip=${wavFile.uri.pathSegments.last} '
          'decode_ms=${decodeStopwatch.elapsedMilliseconds}',
        )
        ..writeln('  $text');
    }
  }
  await engine.shutdown();
}

Future<void> main(List<String> arguments) async {
  final directories = <String>[];
  var modelDirectory = 'models/parakeet-tdt-0.6b-v3-int8';
  var libraryDirectory = _defaultLibraryDirectory();
  var type = 'transducer';
  var engine = 'sherpa';
  var language = 'en';
  var manifestPath = '';
  var dialectFilter = '';
  // A trailing flag with no value is a typo, not a crash: report it
  // instead of letting arguments[++i] throw a RangeError.
  String? value(int index, String flag) {
    if (index + 1 >= arguments.length) {
      stderr.writeln('Missing value after $flag.');
      exitCode = 64;
      return null;
    }
    return arguments[index + 1];
  }

  for (var i = 0; i < arguments.length; i++) {
    final flag = arguments[i];
    if (!flag.startsWith('--')) {
      directories.add(flag);
      continue;
    }
    final argument = value(i++, flag);
    if (argument == null) {
      return;
    }
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
        engine = argument;
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
  if (engine == 'whisper-ggml') {
    await _runWhisperGgml(
      directories,
      modelDirectory,
      language,
      manifestPath,
      dialectFilter,
    );
    return;
  }

  final normalizedLibraryDirectory = libraryDirectory.replaceAll('/', '\\');
  if (normalizedLibraryDirectory.isNotEmpty) {
    // Pre-pin the bundled onnxruntime BEFORE sherpa loads: Windows ML
    // ships an older onnxruntime.dll in System32, which otherwise wins
    // the dependency search and crashes with an ORT API mismatch. (The
    // real app is immune — its own copy sits next to typemate.exe.)
    DynamicLibrary.open('$normalizedLibraryDirectory\\onnxruntime.dll');
  }
  sherpa_onnx.initBindings(
    normalizedLibraryDirectory.isEmpty ? null : normalizedLibraryDirectory,
  );

  final loadStopwatch = Stopwatch()..start();
  final recognizer = sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(
      model: _modelConfig(type, modelDirectory, language),
    ),
  );
  stdout.writeln('model_loaded_ms=${loadStopwatch.elapsedMilliseconds}');

  if (manifestPath.isNotEmpty) {
    await _runManifest(
      (wavPath) async {
        final wave = sherpa_onnx.readWave(wavPath);
        final stream = recognizer.createStream();
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text;
        stream.free();
        return text;
      },
      manifestPath,
      language,
      dialectFilter,
    );
    recognizer.free();
    return;
  }

  for (final directory in directories) {
    for (final wavFile in _wavFiles(directory)) {
      final decodeStopwatch = Stopwatch()..start();
      final wave = sherpa_onnx.readWave(wavFile.path);
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();
      final seconds = (wave.samples.length / wave.sampleRate).toStringAsFixed(
        1,
      );
      stdout
        ..writeln(
          'clip=${wavFile.uri.pathSegments.last} '
          'audio_s=$seconds decode_ms=${decodeStopwatch.elapsedMilliseconds}',
        )
        ..writeln('  $text');
    }
  }
  recognizer.free();
}
