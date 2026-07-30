import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../audio/audio_recorder.dart';
import '../diagnostics/diagnostic_reporter.dart';
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart' show SttRuntimeException;

/// The file names inside a sherpa-onnx Parakeet transducer model
/// directory, shared with the provisioning download list.
const sherpaParakeetModelFileNames = [
  'encoder.int8.onnx',
  'decoder.int8.onnx',
  'joiner.int8.onnx',
  'tokens.txt',
];

/// On-device English/European transcription with NVIDIA Parakeet TDT 0.6B
/// v3 through the sherpa-onnx FFI bindings — the same model the desktop
/// resident server runs, minus the server process (Android cannot spawn
/// bundled executables).
///
/// The recognizer lives in a dedicated long-lived isolate: loading ~620 MB
/// of weights and decoding a clip are blocking FFI calls that would freeze
/// the UI thread. The isolate is the mobile equivalent of the desktop's
/// resident server — one cold load, then every utterance decodes quickly
/// against the warm recognizer.
class SherpaParakeetSttEngine implements DisposableSttEngine {
  SherpaParakeetSttEngine({
    required this.modelDirectoryPath,
    this.numThreads = 2,
    DiagnosticReporter? diagnostics,
  }) : _diagnostics = diagnostics ?? DiagnosticReporter();

  final String modelDirectoryPath;

  /// Decode threads for onnxruntime; two is the sherpa-onnx mobile
  /// guidance (more mostly burns battery for little latency).
  final int numThreads;

  final DiagnosticReporter _diagnostics;

  Isolate? _isolate;
  SendPort? _commands;
  Future<void>? _preparing;

  @override
  Future<bool> isReady() async => _commands != null;

  @override
  Future<void> prepare() async {
    if (_commands != null) {
      return;
    }
    // One cold load at a time; a failed attempt clears so retry works.
    final inFlight = _preparing;
    if (inFlight != null) {
      return inFlight;
    }
    final attempt = _start();
    _preparing = attempt;
    try {
      await attempt;
    } finally {
      _preparing = null;
    }
  }

  Future<void> _start() async {
    for (final name in sherpaParakeetModelFileNames) {
      final path = '$modelDirectoryPath/$name';
      if (!File(path).existsSync()) {
        throw SttRuntimeException(
          'Speech model file is missing: $path. '
          'Download the model from the dictation screen first.',
        );
      }
    }
    final loadStopwatch = Stopwatch()..start();
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(
        readyPort: readyPort.sendPort,
        modelDirectoryPath: modelDirectoryPath,
        numThreads: numThreads,
      ),
      debugName: 'sherpa-parakeet-stt',
    );
    final ready = await readyPort.first;
    readyPort.close();
    if (ready is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw SttRuntimeException('Speech model failed to load: $ready');
    }
    _isolate = isolate;
    _commands = ready;
    _diagnostics.info(
      'engine',
      'parakeet on-device model loaded in '
          '${loadStopwatch.elapsedMilliseconds}ms',
    );
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    await prepare();
    final commands = _commands;
    if (commands == null) {
      throw SttRuntimeException('Speech engine is not loaded.');
    }
    final replyPort = ReceivePort();
    commands.send(_TranscribeRequest(recording.path, replyPort.sendPort));
    final reply = await replyPort.first;
    replyPort.close();
    if (reply is! String) {
      throw SttRuntimeException('On-device transcription failed: $reply');
    }
    return reply;
  }

  @override
  Future<void> shutdown() async {
    _commands?.send(const _ShutdownRequest());
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _commands = null;
  }
}

class _WorkerInit {
  const _WorkerInit({
    required this.readyPort,
    required this.modelDirectoryPath,
    required this.numThreads,
  });

  final SendPort readyPort;
  final String modelDirectoryPath;
  final int numThreads;
}

class _TranscribeRequest {
  const _TranscribeRequest(this.wavPath, this.replyPort);

  final String wavPath;
  final SendPort replyPort;
}

class _ShutdownRequest {
  const _ShutdownRequest();
}

/// Transcription failures cross the isolate boundary as this type so the
/// caller can tell them apart from a successful transcript String.
class _WorkerFailure {
  const _WorkerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> _workerMain(_WorkerInit init) async {
  final sherpa_onnx.OfflineRecognizer recognizer;
  try {
    sherpa_onnx.initBindings();
    final directory = init.modelDirectoryPath;
    recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          transducer: sherpa_onnx.OfflineTransducerModelConfig(
            encoder: '$directory/encoder.int8.onnx',
            decoder: '$directory/decoder.int8.onnx',
            joiner: '$directory/joiner.int8.onnx',
          ),
          tokens: '$directory/tokens.txt',
          modelType: 'nemo_transducer',
          numThreads: init.numThreads,
        ),
      ),
    );
  } catch (error) {
    init.readyPort.send(_WorkerFailure('$error'));
    return;
  }

  final commands = ReceivePort();
  init.readyPort.send(commands.sendPort);
  await for (final message in commands) {
    if (message is _ShutdownRequest) {
      break;
    }
    if (message is! _TranscribeRequest) {
      continue;
    }
    try {
      final wave = sherpa_onnx.readWave(message.wavPath);
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();
      message.replyPort.send(text);
    } catch (error) {
      message.replyPort.send(_WorkerFailure('$error'));
    }
  }
  recognizer.free();
  commands.close();
}
