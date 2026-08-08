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

/// Why [sampleCount]/[sampleRate] must not be handed to the recognizer,
/// or null when they are safe to decode.
///
/// Returns an EMPTY string when nothing was spoken — the honest answer is
/// an empty transcript — and a non-empty reason when the recording could
/// not be read at all, which is a real failure the user should be able to
/// retry from History rather than see reported as silence.
///
/// This exists as a pure function so it can be tested. Feeding either case
/// to sherpa aborts the process natively — an invalid input shape for zero
/// samples, a divide-by-zero building a resampler for a zero sample rate —
/// and a native abort cannot be caught from Dart, so the app simply
/// vanishes with no error and no history entry.
String? parakeetAudioRefusal({
  required int sampleCount,
  required int sampleRate,
}) {
  if (sampleRate <= 0) {
    return 'the recording could not be read';
  }
  if (sampleCount == 0) {
    return '';
  }
  return null;
}

/// On-device transcription with an NVIDIA Parakeet 0.6B transducer
/// (parakeet-unified-en for English, TDT v3 for the 24 multilingual
/// languages) through the sherpa-onnx FFI bindings, on every platform. No
/// server process, no port, no startup handshake: the model loads in this
/// process, so a load failure surfaces as a real exception instead of a
/// connection timeout.
///
/// The recognizer lives in a dedicated long-lived isolate: loading ~620 MB
/// of weights and decoding a clip are blocking FFI calls that would freeze
/// the UI thread. One cold load, then every utterance decodes quickly
/// against the warm recognizer.
class SherpaParakeetSttEngine implements DisposableSttEngine {
  SherpaParakeetSttEngine({
    required this.modelDirectoryPath,
    this.numThreads = 2,
    DiagnosticReporter? diagnostics,
    void Function(SherpaWorkerInit)? workerEntryPoint,
  }) : _diagnostics = diagnostics ?? DiagnosticReporter(),
       _workerEntryPoint = workerEntryPoint ?? _workerMain;

  /// The isolate entrypoint. Tests inject a fake worker so the engine's own
  /// lifecycle — the shutdown handshake, the death handling — is exercised
  /// without loading 654 MB of weights over FFI. Must be a top-level or
  /// static function, as Isolate.spawn requires.
  final void Function(SherpaWorkerInit) _workerEntryPoint;

  final String modelDirectoryPath;

  /// Decode threads for onnxruntime; two is the sherpa-onnx mobile
  /// guidance (more mostly burns battery for little latency).
  final int numThreads;

  final DiagnosticReporter _diagnostics;

  Isolate? _isolate;
  SendPort? _commands;
  Future<void>? _preparing;
  ReceivePort? _deathPort;

  /// Completes when the worker isolate dies (onExit/onError), for the whole
  /// life of the isolate rather than just during startup. Without it a
  /// worker that dies mid-decode leaves `transcribe()` awaiting a reply
  /// that can never arrive, and every later dictation hangs the same way
  /// because the handles still look alive.
  Future<Object?>? _workerDied;

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
          'Download the speech model in the app first.',
        );
      }
    }
    final loadStopwatch = Stopwatch()..start();
    final readyPort = ReceivePort();
    // The worker can die without ever sending a reply — an uncaught error
    // outside its try, or the OS killing it while mapping 620 MB of
    // weights on a memory-tight phone. Without these ports that death
    // would leave prepare() (and the "Preparing speech engine" UI)
    // waiting forever; with them, whichever signal arrives first wins.
    final deathPort = ReceivePort();
    // Kept open for the isolate's whole life, not just startup: the same
    // signal has to unblock a transcribe() whose worker died mid-decode.
    final died = Completer<Object?>();
    deathPort.listen((message) {
      if (!died.isCompleted) {
        died.complete(message);
      }
    });
    final isolate = await Isolate.spawn(
      _workerEntryPoint,
      SherpaWorkerInit(
        readyPort: readyPort.sendPort,
        modelDirectoryPath: modelDirectoryPath,
        numThreads: numThreads,
      ),
      onError: deathPort.sendPort,
      onExit: deathPort.sendPort,
      debugName: 'sherpa-parakeet-stt',
    );
    final ready = await Future.any([
      readyPort.first,
      died.future.then(
        // onExit sends null; onError sends [error, stackTrace].
        (message) => _WorkerFailure(
          message == null
              ? 'the model loader exited before the model finished loading '
                    '(possibly out of memory)'
              : (message as List).first.toString(),
        ),
      ),
    ]);
    readyPort.close();
    if (ready is! SendPort) {
      deathPort.close();
      isolate.kill(priority: Isolate.immediate);
      throw SttRuntimeException('Speech model failed to load: $ready');
    }
    _isolate = isolate;
    _commands = ready;
    _deathPort = deathPort;
    _workerDied = died.future;
    // Drop the handles when the worker dies, so isReady() stops lying and
    // prepare() spawns a fresh one instead of early-returning into a dead
    // isolate for the rest of the process.
    unawaited(died.future.then((_) => _forgetWorker()));
    _diagnostics.info(
      'engine',
      'parakeet on-device model loaded in '
          '${loadStopwatch.elapsedMilliseconds}ms',
    );
  }

  void _forgetWorker() {
    _deathPort?.close();
    _deathPort = null;
    _workerDied = null;
    _commands = null;
    _isolate = null;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    await prepare();
    final commands = _commands;
    if (commands == null) {
      throw SttRuntimeException('Speech engine is not loaded.');
    }
    final replyPort = ReceivePort();
    commands.send(SherpaTranscribeRequest(recording.path, replyPort.sendPort));
    // Race the reply against the worker dying, the same way _start() does:
    // without this a worker killed mid-decode (native abort, OOM) leaves
    // this future pending forever.
    final workerDied = _workerDied;
    final reply = await Future.any([
      replyPort.first,
      if (workerDied != null)
        workerDied.then(
          (message) => _WorkerFailure(
            message == null
                ? 'the model loader exited during transcription'
                : (message as List).first.toString(),
          ),
        ),
    ]);
    replyPort.close();
    if (reply is! String) {
      throw SttRuntimeException('On-device transcription failed: $reply');
    }
    return reply;
  }

  /// How long shutdown waits for the worker to free the native recognizer
  /// before killing it anyway.
  static const shutdownAckTimeout = Duration(seconds: 5);

  @override
  Future<void> shutdown() async {
    final commands = _commands;
    final isolate = _isolate;
    _commands = null;
    _isolate = null;
    if (commands != null) {
      // Wait for the worker to acknowledge, because the acknowledgement is
      // sent AFTER recognizer.free(). Killing straight after sending the
      // request usually preempted that call, so the model's native weights
      // (a C++ allocation the Dart GC never touches) survived a language
      // switch — exactly what the RAM policy exists to prevent.
      final freedPort = ReceivePort();
      try {
        commands.send(SherpaShutdownRequest(freedPort.sendPort));
        await freedPort.first.timeout(shutdownAckTimeout);
      } catch (error) {
        _diagnostics.info(
          'engine',
          'parakeet worker did not confirm shutdown, killing it: $error',
        );
      } finally {
        freedPort.close();
      }
    }
    // Always kill: the backstop for a wedged worker, and a no-op once the
    // worker has already exited on its own.
    isolate?.kill(priority: Isolate.beforeNextEvent);
    _forgetWorker();
  }
}

/// The worker protocol is public so tests can inject a fake worker
/// entrypoint: the real one loads a 654 MB model over FFI, so the engine's
/// own lifecycle (shutdown handshake, death handling) is otherwise
/// unreachable from a unit test.
class SherpaWorkerInit {
  const SherpaWorkerInit({
    required this.readyPort,
    required this.modelDirectoryPath,
    required this.numThreads,
  });

  final SendPort readyPort;
  final String modelDirectoryPath;
  final int numThreads;
}

class SherpaTranscribeRequest {
  const SherpaTranscribeRequest(this.wavPath, this.replyPort);

  final String wavPath;
  final SendPort replyPort;
}

class SherpaShutdownRequest {
  const SherpaShutdownRequest(this.freedPort);

  /// Signalled once the worker has released the native recognizer, so the
  /// caller can wait for the model's C++ memory to actually go.
  final SendPort freedPort;
}

/// Transcription failures cross the isolate boundary as this type so the
/// caller can tell them apart from a successful transcript String.
class _WorkerFailure {
  const _WorkerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> _workerMain(SherpaWorkerInit init) async {
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
  SherpaShutdownRequest? shutdown;
  await for (final message in commands) {
    if (message is SherpaShutdownRequest) {
      shutdown = message;
      break;
    }
    if (message is! SherpaTranscribeRequest) {
      continue;
    }
    try {
      final wave = sherpa_onnx.readWave(message.wavPath);
      final refusal = parakeetAudioRefusal(
        sampleCount: wave.samples.length,
        sampleRate: wave.sampleRate,
      );
      if (refusal != null) {
        message.replyPort.send(refusal.isEmpty ? '' : _WorkerFailure(refusal));
        continue;
      }
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        message.replyPort.send(recognizer.getResult(stream).text);
      } finally {
        // Freed on every path: the failure path used to leak a native
        // stream for the life of the isolate.
        stream.free();
      }
    } catch (error) {
      message.replyPort.send(_WorkerFailure('$error'));
    }
  }
  // Free BEFORE acknowledging: the whole point of the handshake is that the
  // caller learns the native recognizer is gone, not merely that the
  // request was received.
  recognizer.free();
  commands.close();
  shutdown?.freedPort.send(null);
}
