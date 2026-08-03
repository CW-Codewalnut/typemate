// Proves real English transcription through the in-process sherpa-onnx
// Parakeet recognizer — the exact model files and recognizer config
// SherpaParakeetSttEngine loads on every platform — against the persistent
// benchmark corpus.
//
// Usage (pure Dart, no Flutter runtime needed):
//   dart run tool/benchmark_parakeet_inprocess.dart \
//     [--model-dir models/parakeet-tdt-0.6b-v3-int8] [--lib-dir <dll dir>]
//
// --lib-dir points at the directory holding sherpa-onnx-c-api.dll (and
// onnxruntime.dll). It defaults to the sherpa_onnx_windows pub-cache copy
// so the tool runs after a plain `flutter pub get`.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

const _corpusDirectory = 'test_assets/stt_benchmark';

String _defaultLibraryDirectory() {
  final home = Platform.environment['USERPROFILE'] ?? '';
  final pubCache =
      '$home/AppData/Local/Pub/Cache/hosted/pub.dev/'
      'sherpa_onnx_windows-1.13.4/windows';
  return Directory(pubCache).existsSync() ? pubCache : '';
}

Future<void> main(List<String> arguments) async {
  var modelDirectory = 'models/parakeet-tdt-0.6b-v3-int8';
  var libraryDirectory = _defaultLibraryDirectory();
  for (var i = 0; i < arguments.length - 1; i++) {
    if (arguments[i] == '--model-dir') {
      modelDirectory = arguments[i + 1];
    }
    if (arguments[i] == '--lib-dir') {
      libraryDirectory = arguments[i + 1];
    }
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
  // Identical config to SherpaParakeetSttEngine's worker isolate.
  final recognizer = sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        transducer: sherpa_onnx.OfflineTransducerModelConfig(
          encoder: '$modelDirectory/encoder.int8.onnx',
          decoder: '$modelDirectory/decoder.int8.onnx',
          joiner: '$modelDirectory/joiner.int8.onnx',
        ),
        tokens: '$modelDirectory/tokens.txt',
        modelType: 'nemo_transducer',
        numThreads: 4,
      ),
    ),
  );
  stdout.writeln('model_loaded_ms=${loadStopwatch.elapsedMilliseconds}');

  final manifest =
      jsonDecode(File('$_corpusDirectory/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final clips = (manifest['clips'] as List).cast<Map<String, dynamic>>();
  for (final clip in clips.where((c) => c['language'] == 'en')) {
    final wavPath = '$_corpusDirectory/${clip['file']}';
    final decodeStopwatch = Stopwatch()..start();
    final wave = sherpa_onnx.readWave(wavPath);
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text;
    stream.free();
    stdout
      ..writeln(
        'clip=${clip['file']} decode_ms=${decodeStopwatch.elapsedMilliseconds}',
      )
      ..writeln('  expected: ${clip['expected']}')
      ..writeln('  got:      $text');
  }
  recognizer.free();
}
