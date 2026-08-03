import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show BytesBuilder;

import 'package:ffi/ffi.dart';

import '../audio/audio_recorder.dart';
import '../diagnostics/diagnostic_reporter.dart';
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart' show SttRuntimeException;

/// Whisper transcription through the whisper_ggml plugin's native layer,
/// in-process on every platform — the same architecture as the Parakeet
/// engine: no server process, no port, no startup handshake.
///
/// This is a thin FFI client of the plugin's JSON `request` symbol rather
/// than its Dart API: the engine needs no Flutter binding (so the corpus
/// benchmark can drive it from plain `dart run`), it skips the plugin's
/// audio-conversion step (recordings are already 16 kHz mono WAV), and it
/// owns response memory correctly.
///
/// The model loads once (patched fork: `keep_model_loaded`) and stays
/// resident in native process globals, so every isolate sees the warm
/// context; Silero VAD trims hold-to-talk silence before decoding —
/// without it whisper loops and repeats sentences over the silent
/// lead/tail.
class WhisperGgmlSttEngine implements DisposableSttEngine {
  WhisperGgmlSttEngine({
    required this.modelPath,
    required this.language,
    required this.vadModelPath,
    this.prompt,
    this.numThreads = 6,
    DiagnosticReporter? diagnostics,
    bool Function(String path)? modelFileExists,
    Future<String> Function(String payload)? requestRunner,
  }) : _diagnostics = diagnostics ?? DiagnosticReporter(),
       _modelFileExists = modelFileExists ?? _fileExists,
       _requestRunner = requestRunner ?? _isolateRequest;

  final String modelPath;

  /// Whisper's language flag (e.g. 'hi' — also used for Hinglish, whose
  /// fine-tune romanizes on its own).
  final String language;

  final String vadModelPath;

  /// Optional initial prompt (e.g. Hindi's Devanagari script prompt).
  final String? prompt;

  final int numThreads;

  final DiagnosticReporter _diagnostics;
  final bool Function(String path) _modelFileExists;

  /// Sends one JSON request to the native layer; tests inject a fake.
  final Future<String> Function(String payload) _requestRunner;

  bool _warm = false;

  @override
  Future<bool> isReady() async => _warm;

  @override
  Future<void> prepare() async {
    if (_warm) {
      return;
    }
    _requireModel();
    // Warm the resident model with a beat of silence: VAD finds no
    // speech, so this costs one model load and returns immediately.
    final loadStopwatch = Stopwatch()..start();
    final silence = _writeSilenceWav();
    try {
      await _transcribeFile(silence.path);
    } finally {
      _deleteQuietly(silence);
    }
    _warm = true;
    _diagnostics.info(
      'engine',
      'whisper "$language" model loaded in '
          '${loadStopwatch.elapsedMilliseconds}ms',
    );
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    _requireModel();
    final text = await _transcribeFile(recording.path);
    _warm = true;
    return _cleanTranscript(text);
  }

  @override
  Future<void> shutdown() async {
    if (!_warm) {
      return;
    }
    _warm = false;
    await _requestRunner(json.encode({'@type': 'releaseModel'}));
  }

  void _requireModel() {
    if (!_modelFileExists(modelPath)) {
      throw SttRuntimeException(
        'The speech model for this language is not downloaded yet '
        '($modelPath). Download it in the app first.',
      );
    }
  }

  Future<String> _transcribeFile(String wavPath) async {
    final payload = json.encode({
      '@type': 'getTextFromWavFile',
      'audio': wavPath,
      'model': modelPath,
      'is_translate': false,
      'threads': numThreads,
      'is_verbose': false,
      'language': language,
      'is_special_tokens': false,
      'is_no_timestamps': true,
      'n_processors': 1,
      'split_on_word': false,
      'no_fallback': true,
      'is_realtime': false,
      'diarize': false,
      'speed_up': false,
      'initial_prompt': prompt,
      // Short single utterances: prior-segment context only invites
      // repetition.
      'no_context': true,
      'suppress_non_speech_tokens': false,
      'progress_callback': null,
      'keep_model_loaded': true,
      'vad_model': vadModelPath,
      // Keeps the first word intact; larger padding garbles segment
      // boundaries (same value the retired servers used).
      'vad_speech_pad_ms': 100,
    });
    final response = await _requestRunner(payload);
    final decoded = json.decode(response) as Map<String, dynamic>;
    if (decoded['text'] == null) {
      throw SttRuntimeException(
        'On-device transcription failed: '
        '${decoded['message'] ?? 'unknown whisper error'}',
      );
    }
    return decoded['text'] as String;
  }

  /// Whisper output can carry replacement characters from token-boundary
  /// artifacts and hard-wrapped lines; dictation wants one clean line.
  String _cleanTranscript(String text) {
    return text
        .replaceAll('\u{FFFD}', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  File _writeSilenceWav() {
    const sampleRate = 16000;
    const samples = sampleRate ~/ 2; // 0.5s
    const dataBytes = samples * 2;
    final header = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(_int32le(36 + dataBytes))
      ..add(ascii.encode('WAVE'))
      ..add(ascii.encode('fmt '))
      ..add(_int32le(16))
      ..add(_int16le(1)) // PCM
      ..add(_int16le(1)) // mono
      ..add(_int32le(sampleRate))
      ..add(_int32le(sampleRate * 2))
      ..add(_int16le(2))
      ..add(_int16le(16))
      ..add(ascii.encode('data'))
      ..add(_int32le(dataBytes))
      ..add(List.filled(dataBytes, 0));
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'typemate-warmup-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    file.writeAsBytesSync(header.takeBytes(), flush: true);
    return file;
  }

  static List<int> _int32le(int value) => [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];

  static List<int> _int16le(int value) => [value & 0xff, (value >> 8) & 0xff];

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Temp litter; the OS temp cleaner gets it eventually.
    }
  }

  static bool _fileExists(String path) => File(path).existsSync();
}

typedef _WReqNative = Pointer<Utf8> Function(Pointer<Utf8>);

/// Default request path: the blocking FFI call runs off the main isolate;
/// the resident model lives in native process globals, so every isolate
/// reuses it.
Future<String> _isolateRequest(String payload) {
  return Isolate.run(() => _request(payload));
}

/// Whether to leak native responses instead of freeing them. The native
/// side mallocs the response specifically so the caller can free it with
/// the C allocator. In-app both modules share the release CRT; standalone
/// harnesses against a debug-built DLL have mismatched CRT heaps and must
/// leak the few bytes instead (benchmark tools set this). Read once per
/// isolate, not per request.
final bool _leakResponses =
    Platform.environment['TYPEMATE_GGML_NO_FREE'] == '1';

/// Sends one JSON request to the plugin's native `request` symbol and
/// returns the response JSON. Runs inside a worker isolate; the library
/// handle is cheap to reopen (the OS caches the loaded module).
String _request(String payload) {
  final lib = _openLibrary();
  final request = lib.lookupFunction<_WReqNative, _WReqNative>('request');
  final data = payload.toNativeUtf8();
  try {
    final res = request(data);
    try {
      return res.toDartString();
    } finally {
      if (!_leakResponses) {
        malloc.free(res);
      }
    }
  } finally {
    malloc.free(data);
  }
}

DynamicLibrary _openLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libwhisper.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('whisper_ggml.dll');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libwhisper_ggml.so');
  }
  return DynamicLibrary.process();
}
