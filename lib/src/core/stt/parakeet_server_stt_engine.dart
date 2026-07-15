import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../audio/audio_recorder.dart';
import 'stt_engine.dart';
import 'whisper_cli_stt_engine.dart' show SttRuntimeException;

typedef ServerProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

typedef WebSocketConnector = Future<SttServerSocket> Function(String url);

/// Minimal socket surface so tests can fake the websocket transport.
abstract interface class SttServerSocket {
  void add(List<int> data);
  Stream<dynamic> get messages;
  Future<void> close();
}

class _WebSocketSttServerSocket implements SttServerSocket {
  _WebSocketSttServerSocket(this._socket)
    : messages = _socket.asBroadcastStream();

  final WebSocket _socket;

  @override
  final Stream<dynamic> messages;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}

Future<Process> _startServerProcess(
  String executable,
  List<String> arguments,
) => Process.start(executable, arguments);

Future<SttServerSocket> _connectWebSocket(String url) async =>
    _WebSocketSttServerSocket(
      await WebSocket.connect(url).timeout(const Duration(seconds: 2)),
    );

/// English transcription through a resident sherpa-onnx server running the
/// NVIDIA Parakeet TDT 0.6B v3 model. The server loads the 622MB model once
/// at startup; each utterance then decodes in well under a second, where a
/// spawn-per-utterance design would pay ~4.5s of model loading every time.
class ParakeetServerSttEngine implements DisposableSttEngine {
  ParakeetServerSttEngine({
    required this.serverExecutable,
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    this.port = 43007,
    this.startupTimeout = const Duration(seconds: 60),
    ServerProcessStarter? processStarter,
    WebSocketConnector? webSocketConnector,
  }) : processStarter = processStarter ?? _startServerProcess,
       webSocketConnector = webSocketConnector ?? _connectWebSocket;

  final String serverExecutable;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final int port;
  final Duration startupTimeout;
  final ServerProcessStarter processStarter;
  final WebSocketConnector webSocketConnector;

  Process? _serverProcess;

  String get _url => 'ws://127.0.0.1:$port';

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

    final wav = await File(recording.path).readAsBytes();
    final audio = decodePcm16Wav(wav);
    final socket = await webSocketConnector(_url);
    try {
      socket.add(buildSherpaAudioMessage(audio.sampleRate, audio.samples));
      final response = await socket.messages.first.timeout(
        const Duration(seconds: 60),
      );
      return _parseTranscript(response);
    } finally {
      await socket.close();
    }
  }

  @override
  Future<void> shutdown() async {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  Future<void> _ensureServerRunning() async {
    // An already-reachable server (from this run or an earlier app run that
    // did not exit cleanly) is adopted instead of spawning a duplicate.
    if (await _canConnect()) {
      return;
    }

    _serverProcess?.kill();
    _serverProcess = await processStarter(serverExecutable, [
      '--port=$port',
      '--encoder=$encoderPath',
      '--decoder=$decoderPath',
      '--joiner=$joinerPath',
      '--tokens=$tokensPath',
      // No --model-type: Parakeet is a NeMo transducer, which the server's
      // model-type shortcut list does not cover; auto-detection handles it.
      '--num-work-threads=4',
    ]);
    // The server logs verbosely while loading the model; without draining,
    // the full OS pipe buffer blocks it before it ever starts listening.
    unawaited(_serverProcess!.stdout.drain<void>());
    unawaited(_serverProcess!.stderr.drain<void>());

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _canConnect()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    _serverProcess?.kill();
    _serverProcess = null;
    throw const SttRuntimeException(
      'The local English speech server did not start. '
      'Check the sherpa-onnx runtime and the Parakeet model files.',
    );
  }

  Future<bool> _canConnect() async {
    try {
      final socket = await webSocketConnector(_url);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _parseTranscript(dynamic response) {
    if (response is! String) {
      throw const SttRuntimeException(
        'The local English speech server returned an unexpected response.',
      );
    }
    final decoded = jsonDecode(response);
    if (decoded case {'text': final String text}) {
      return text.trim();
    }
    throw const SttRuntimeException(
      'The local English speech server returned an unexpected response.',
    );
  }
}

class DecodedWavAudio {
  const DecodedWavAudio({required this.sampleRate, required this.samples});

  final int sampleRate;
  final Float32List samples;
}

/// Decodes a 16-bit PCM RIFF/WAV file into normalized float samples.
DecodedWavAudio decodePcm16Wav(Uint8List wavBytes) {
  if (wavBytes.length < 44 ||
      ascii.decode(wavBytes.sublist(0, 4)) != 'RIFF' ||
      ascii.decode(wavBytes.sublist(8, 12)) != 'WAVE') {
    throw const SttRuntimeException('Recording is not a RIFF/WAVE file.');
  }

  final data = ByteData.sublistView(wavBytes);
  var sampleRate = 0;
  var bitsPerSample = 0;
  var offset = 12;
  while (offset + 8 <= wavBytes.length) {
    final chunkId = ascii.decode(wavBytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    if (chunkId == 'fmt ') {
      sampleRate = data.getUint32(offset + 12, Endian.little);
      bitsPerSample = data.getUint16(offset + 22, Endian.little);
    } else if (chunkId == 'data') {
      if (bitsPerSample != 16) {
        throw const SttRuntimeException('Recording is not 16-bit PCM audio.');
      }
      final sampleCount = chunkSize ~/ 2;
      final samples = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        samples[i] = data.getInt16(offset + 8 + i * 2, Endian.little) / 32768;
      }
      return DecodedWavAudio(sampleRate: sampleRate, samples: samples);
    }
    offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  throw const SttRuntimeException('Recording has no PCM data chunk.');
}

/// Frames audio for the sherpa-onnx offline websocket protocol:
/// int32le sample rate, int32le payload byte count, float32le samples.
Uint8List buildSherpaAudioMessage(int sampleRate, Float32List samples) {
  final message = ByteData(8 + samples.length * 4);
  message.setInt32(0, sampleRate, Endian.little);
  message.setInt32(4, samples.length * 4, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    message.setFloat32(8 + i * 4, samples[i], Endian.little);
  }
  return message.buffer.asUint8List();
}
