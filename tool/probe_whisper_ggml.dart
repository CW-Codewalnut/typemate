// Temporary crash-isolation probe: drives the built whisper_ggml.dll
// directly with one request so native stderr (whisper.cpp logs) is
// visible in the console.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _WReqNative = Pointer<Utf8> Function(Pointer<Utf8>);

Future<void> main(List<String> arguments) async {
  final root = Directory.current.path.replaceAll('\\', '/');
  final lib = DynamicLibrary.open(
    '$root/build/windows/x64/runner/Debug/whisper_ggml.dll',
  );
  final request = lib.lookupFunction<_WReqNative, _WReqNative>('request');

  final model = arguments.isNotEmpty
      ? arguments.first
      : '$root/models/ggml-small-vaani-hindi-q6.bin';
  final clip = arguments.length > 1
      ? arguments[1]
      : '$root/test_assets/stt_benchmark/hi-market.wav';
  final staged = '${Directory.systemTemp.path}/ggml-probe.wav';
  File(clip).copySync(staged);

  final payload = json.encode({
    '@type': 'getTextFromWavFile',
    'audio': staged,
    'model': model,
    'is_translate': false,
    'threads': 6,
    'is_verbose': true,
    'language': arguments.length > 2 ? arguments[2] : 'hi',
    'is_special_tokens': false,
    'is_no_timestamps': true,
    'n_processors': 1,
    'split_on_word': false,
    'no_fallback': false,
    'is_realtime': false,
    'diarize': false,
    'speed_up': false,
    'initial_prompt': null,
    'no_context': true,
    'suppress_non_speech_tokens': false,
    'progress_callback': null,
    // Patched fork: resident model; audio_ctx from argv (0 = full window);
    // Silero VAD with the production 100ms pad (same as the servers).
    'keep_model_loaded': true,
    'audio_ctx': arguments.length > 3 ? int.parse(arguments[3]) : 0,
    'vad_model': '$root/models/ggml-silero-v5.1.2.bin',
    'vad_speech_pad_ms': 100,
  });

  stdout.writeln('probe_start model=$model');
  for (var i = 0; i < 3; i++) {
    final stopwatch = Stopwatch()..start();
    final data = payload.toNativeUtf8();
    final res = request(data);
    stdout.writeln('probe_run$i ms=${stopwatch.elapsedMilliseconds}');
    stdout.writeln('probe_text=${res.toDartString()}');
    malloc.free(data);
    // res deliberately leaked: freeing memory malloc'd inside the debug-CRT
    // plugin DLL from dart.exe's CRT corrupts the heap (crash isolation).
  }
  File(staged).deleteSync();
}
