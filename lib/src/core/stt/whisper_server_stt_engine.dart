import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../audio/audio_recorder.dart';
import 'parakeet_server_stt_engine.dart' show ServerProcessStarter;
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart' show SttRuntimeException;

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
  Map<String, String> fields,
) async {
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
    final response = await request.close().timeout(const Duration(seconds: 60));
    final responseBody = await response.transform(utf8.decoder).join();
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
    ServerProcessStarter? processStarter,
    ServerConnectionProbe? connectionProbe,
    WhisperInferenceClient? inferenceClient,
  }) : processStarter = processStarter ?? _startServerProcess,
       connectionProbe = connectionProbe ?? _probeTcpPort,
       inferenceClient = inferenceClient ?? _postMultipartInference;

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
  final ServerProcessStarter processStarter;
  final ServerConnectionProbe connectionProbe;
  final WhisperInferenceClient inferenceClient;

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

    _serverProcess?.kill();
    _serverProcess = await processStarter(serverExecutable, [
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
    unawaited(_serverProcess!.stdout.drain<void>());
    unawaited(_serverProcess!.stderr.drain<void>());

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await connectionProbe(port)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    _serverProcess?.kill();
    _serverProcess = null;
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
