import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../audio/audio_recorder.dart';
import '../diagnostics/diagnostic_log.dart';
import '../diagnostics/diagnostic_reporter.dart';
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart' show SttRuntimeException;

/// Starts a resident speech server process; injectable for tests.
typedef ServerProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Posts a multipart inference request; returns the response body.
typedef WhisperInferenceClient =
    Future<String> Function(
      Uri url,
      String audioFilePath,
      Map<String, String> fields,
    );

/// Probes whether a server is accepting connections on [port].
typedef ServerConnectionProbe = Future<bool> Function(int port);

Future<Process> _startServerProcess(
  String executable,
  List<String> arguments,
) => Process.start(executable, arguments);

bool _modelFileExists(String path) => File(path).existsSync();

Future<bool> _probeTcpPort(int port) async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<String> _postMultipartInference(
  Uri url,
  String audioFilePath,
  Map<String, String> fields, {
  Duration responseTimeout = const Duration(seconds: 60),
  Duration bodyReadTimeout = const Duration(seconds: 30),
}) async {
  final client = HttpClient();
  try {
    const boundary = 'typemate-inference-boundary';
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );

    final body = BytesBuilder();
    void addField(String name, String value) {
      body.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$name"\r\n\r\n'
          '$value\r\n',
        ),
      );
    }

    fields.forEach(addField);
    body.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; '
        'filename="recording.wav"\r\n'
        'Content-Type: audio/wav\r\n\r\n',
      ),
    );
    body.add(await File(audioFilePath).readAsBytes());
    body.add(utf8.encode('\r\n--$boundary--\r\n'));

    request.add(body.takeBytes());
    final response = await request.close().timeout(responseTimeout);
    // The headers arriving does not guarantee the body ever finishes; a
    // stalled server must not strand dictation in "Transcribing" forever.
    final responseBody = await response
        .transform(utf8.decoder)
        .join()
        .timeout(bodyReadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw SttRuntimeException(
        'The local speech server rejected the request '
        '(HTTP ${response.statusCode}).',
      );
    }
    return responseBody;
  } finally {
    client.close();
  }
}

/// Transcription through a resident whisper.cpp HTTP server that keeps one
/// GGML model loaded. Used for Hindi and Hinglish so switching to those
/// languages does not pay a model load per utterance, while only the
/// selected language's server occupies RAM.
class WhisperServerSttEngine implements DisposableSttEngine {
  WhisperServerSttEngine({
    required this.serverExecutable,
    required this.modelPath,
    required this.vadModelPath,
    required this.cliLanguage,
    required this.port,
    this.prompt,
    this.startupTimeout = const Duration(seconds: 30),
    this.responseTimeout = const Duration(seconds: 60),
    this.bodyReadTimeout = const Duration(seconds: 30),
    this.diagnostics,
    ServerProcessStarter? processStarter,
    ServerConnectionProbe? connectionProbe,
    WhisperInferenceClient? inferenceClient,
    bool Function(String path)? modelFileExists,
  }) : processStarter = processStarter ?? _startServerProcess,
       connectionProbe = connectionProbe ?? _probeTcpPort,
       modelFileExists = modelFileExists ?? _modelFileExists,
       _injectedInferenceClient = inferenceClient;

  final String serverExecutable;
  final String modelPath;
  final String vadModelPath;

  /// The whisper language flag (e.g. 'hi' — also used for Hinglish, whose
  /// fine-tune romanizes on its own).
  final String cliLanguage;

  /// Optional initial prompt, sent per request to avoid command-line
  /// encoding issues with non-ASCII text.
  final String? prompt;

  final int port;
  final Duration startupTimeout;

  /// How long the server may decode before the request is abandoned.
  final Duration responseTimeout;

  /// How long the response body may take after the headers arrived.
  final Duration bodyReadTimeout;

  final ServerProcessStarter processStarter;
  final ServerConnectionProbe connectionProbe;

  /// Whether the model file exists on disk; injectable so tests with fake
  /// paths can bypass the real filesystem.
  final bool Function(String path) modelFileExists;

  final WhisperInferenceClient? _injectedInferenceClient;

  /// Records server lifecycle events and startup failures (with a stderr
  /// tail) for troubleshooting; null in tests that don't assert on it.
  final DiagnosticReporter? diagnostics;

  WhisperInferenceClient get inferenceClient =>
      _injectedInferenceClient ??
      ((url, audioFilePath, fields) => _postMultipartInference(
        url,
        audioFilePath,
        fields,
        responseTimeout: responseTimeout,
        bodyReadTimeout: bodyReadTimeout,
      ));

  Process? _serverProcess;

  Uri get _inferenceUrl => Uri.parse('http://127.0.0.1:$port/inference');

  @override
  Future<bool> isReady() async {
    try {
      await prepare();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> prepare() => _ensureServerRunning();

  @override
  Future<String> transcribe(AudioRecording recording) async {
    await _ensureServerRunning();

    final fields = <String, String>{
      'response_format': 'json',
      'temperature': '0.0',
      ..._audioContextField(recording.duration),
      'prompt': ?prompt,
    };
    final body = await inferenceClient(_inferenceUrl, recording.path, fields);
    return _parseTranscript(body);
  }

  @override
  Future<void> shutdown() async {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  // Same clip-sized encoder window as the CLI engine; the server accepts it
  // per request.
  static const _fullAudioContextFrames = 1500;
  static const _minimumAudioContextFrames = 128;
  static const _audioContextMarginSeconds = 2.0;

  Map<String, String> _audioContextField(Duration duration) {
    if (duration <= Duration.zero) {
      return const {};
    }
    final paddedSeconds =
        duration.inMilliseconds / 1000 + _audioContextMarginSeconds;
    if (paddedSeconds >= 30) {
      return const {};
    }
    final frames = (paddedSeconds / 30 * _fullAudioContextFrames).ceil();
    final context = frames < _minimumAudioContextFrames
        ? _minimumAudioContextFrames
        : frames;
    return {'audio_ctx': '$context'};
  }

  Future<void> _ensureServerRunning() async {
    // Adopt an already-reachable server on our port (this run or an orphan
    // from an unclean exit) instead of spawning a duplicate.
    if (await connectionProbe(port)) {
      return;
    }

    // Fail fast with the real reason when the model is not on disk yet
    // (desktop downloads models on demand); spawning the server anyway
    // would burn the full startup timeout on a doomed process.
    if (!modelFileExists(modelPath)) {
      throw SttRuntimeException(
        'The speech model for this language is not downloaded yet '
        '($modelPath). Download it in the app first.',
      );
    }

    _serverProcess?.kill();
    diagnostics?.info(
      'stt',
      'starting whisper server for "$cliLanguage" on port $port '
          '($serverExecutable)',
    );
    final startupStopwatch = Stopwatch()..start();
    final Process process;
    try {
      process = await processStarter(serverExecutable, [
        '-m',
        modelPath,
        '--port',
        '$port',
        '-l',
        cliLanguage,
        '--beam-size',
        '1',
        '--vad',
        '--vad-model',
        vadModelPath,
        '--vad-speech-pad-ms',
        '100',
      ]);
    } catch (error) {
      _serverProcess = null;
      diagnostics?.failure(
        'stt',
        'whisper-spawn-failed',
        'could not start the whisper server process (port $port): $error',
      );
      rethrow;
    }
    _serverProcess = process;
    // Drain stdout so the pipe never blocks the server; stderr keeps a
    // bounded tail so a startup failure can say why.
    final stderrTail = DiagnosticTailBuffer();
    unawaited(process.stdout.drain<void>());
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(stderrTail.add, onError: (_) {}, cancelOnError: false);
    // An early exit (crash, missing DLL, unsupported CPU) shows up in the
    // log as an exit code instead of a silent startup timeout.
    unawaited(
      process.exitCode.then(
        (code) => diagnostics?.info(
          'stt',
          'whisper server (port $port) exited with code $code',
        ),
      ),
    );

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await connectionProbe(port)) {
        diagnostics?.info(
          'stt',
          'whisper server (port $port) ready in '
              '${startupStopwatch.elapsedMilliseconds}ms',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    _serverProcess?.kill();
    _serverProcess = null;
    diagnostics?.failure(
      'stt',
      'whisper-start-timeout',
      'whisper server (port $port) did not accept connections within '
          '${startupTimeout.inSeconds}s'
          '${stderrTail.isEmpty ? '' : '; stderr tail:\n${stderrTail.tail}'}',
    );
    throw const SttRuntimeException(
      'The local speech server did not start. '
      'Check the whisper.cpp runtime and the model file.',
    );
  }

  String _parseTranscript(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const SttRuntimeException(
        'The local speech server returned an unexpected response.',
      );
    }
    if (decoded case {'text': final String text}) {
      // The server occasionally emits a replacement character at a VAD
      // segment boundary, and wraps long lines with newlines.
      return text
          .replaceAll('\u{FFFD}', '')
          .replaceAll('\n', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    throw const SttRuntimeException(
      'The local speech server returned an unexpected response.',
    );
  }
}
