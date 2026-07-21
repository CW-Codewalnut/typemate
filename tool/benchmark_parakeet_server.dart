import 'dart:io';

import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/parakeet_server_stt_engine.dart';

/// Proves the resident English server end-to-end: starts (or adopts) the
/// sherpa-onnx server with the bundled Parakeet model, transcribes the given
/// WAV twice, and reports cold vs warm latency.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/benchmark_parakeet_server.dart <sample.wav>',
    );
    exitCode = 64;
    return;
  }

  final engine = ParakeetServerSttEngine(
    serverExecutable:
        'bin/sherpa/sherpa-onnx-offline-websocket-server'
        '${Platform.isWindows ? '.exe' : ''}',
    encoderPath: 'models/parakeet-tdt-0.6b-v3-int8/encoder.int8.onnx',
    decoderPath: 'models/parakeet-tdt-0.6b-v3-int8/decoder.int8.onnx',
    joinerPath: 'models/parakeet-tdt-0.6b-v3-int8/joiner.int8.onnx',
    tokensPath: 'models/parakeet-tdt-0.6b-v3-int8/tokens.txt',
  );

  final recording = AudioRecording(
    path: arguments.first,
    duration: Duration.zero,
  );

  final coldStopwatch = Stopwatch()..start();
  final first = await engine.transcribe(recording);
  coldStopwatch.stop();
  stdout.writeln('cold_ms=${coldStopwatch.elapsedMilliseconds}');
  stdout.writeln('transcript=$first');

  for (var i = 0; i < 4; i++) {
    final warmStopwatch = Stopwatch()..start();
    await engine.transcribe(recording);
    warmStopwatch.stop();
    stdout.writeln('warm${i + 1}_ms=${warmStopwatch.elapsedMilliseconds}');
  }

  await engine.shutdown();
}
