import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/parakeet_server_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttRuntimeException;

void main() {
  group('decodePcm16Wav', () {
    test('decodes sample rate and normalized samples', () {
      final wav = buildTestWav(
        sampleRate: 16000,
        samples: [0, 16384, -16384, 32767],
      );

      final decoded = decodePcm16Wav(wav);

      expect(decoded.sampleRate, 16000);
      expect(decoded.samples, hasLength(4));
      expect(decoded.samples[0], 0);
      expect(decoded.samples[1], closeTo(0.5, 0.001));
      expect(decoded.samples[2], closeTo(-0.5, 0.001));
      expect(decoded.samples[3], closeTo(1.0, 0.001));
    });

    test('rejects non-wav bytes', () {
      expect(
        () => decodePcm16Wav(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<SttRuntimeException>()),
      );
    });
  });

  group('buildSherpaAudioMessage', () {
    test('frames sample rate, byte count, and float samples', () {
      final message = buildSherpaAudioMessage(
        16000,
        Float32List.fromList([0.5, -0.25]),
      );

      final data = ByteData.sublistView(message);
      expect(data.getInt32(0, Endian.little), 16000);
      expect(data.getInt32(4, Endian.little), 8);
      expect(data.getFloat32(8, Endian.little), 0.5);
      expect(data.getFloat32(12, Endian.little), -0.25);
    });
  });

  group('ParakeetServerSttEngine', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('parakeet-test');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    Future<String> writeWav() async {
      final file = File('${temp.path}/clip.wav');
      await file.writeAsBytes(
        buildTestWav(sampleRate: 16000, samples: [100, -100, 200]),
      );
      return file.path;
    }

    test('starts the server once and transcribes over the socket', () async {
      final transport = FakeTransport(
        response: '{"text": " Hello from Parakeet. "}',
      );
      final engine = buildEngine(transport);

      final wavPath = await writeWav();
      final transcript = await engine.transcribe(
        AudioRecording(path: wavPath, duration: const Duration(seconds: 1)),
      );

      expect(transcript, 'Hello from Parakeet.');
      expect(transport.startedProcesses, hasLength(1));
      final arguments = transport.startedArguments.single.join(' ');
      expect(arguments, contains('--port=43007'));
      expect(arguments, contains('--encoder=encoder.onnx'));
      expect(arguments, contains('--tokens=tokens.txt'));

      // A second transcription reuses the running server.
      await engine.transcribe(
        AudioRecording(path: wavPath, duration: const Duration(seconds: 1)),
      );
      expect(transport.startedProcesses, hasLength(1));
    });

    test(
      'adopts an already-running server instead of starting another',
      () async {
        final transport = FakeTransport(
          response: '{"text": "adopted"}',
          alreadyRunning: true,
        );
        final engine = buildEngine(transport);

        final transcript = await engine.transcribe(
          AudioRecording(
            path: await writeWav(),
            duration: const Duration(seconds: 1),
          ),
        );

        expect(transcript, 'adopted');
        expect(transport.startedProcesses, isEmpty);
      },
    );

    test(
      'throws a clear error when the server never becomes reachable',
      () async {
        final transport = FakeTransport(
          response: '{"text": "x"}',
          serverEverStarts: false,
        );
        final engine = buildEngine(transport, startupTimeout: Duration.zero);

        expect(
          engine.prepare,
          throwsA(
            isA<SttRuntimeException>().having(
              (error) => error.message,
              'message',
              contains('English speech server'),
            ),
          ),
        );
      },
    );

    test('transcribes even when the socket close handshake hangs', () async {
      final transport = FakeTransport(
        response: '{"text": "closed late"}',
        closeHangs: true,
      );
      final engine = buildEngine(
        transport,
        socketCloseTimeout: const Duration(milliseconds: 50),
      );

      final transcript = await engine.transcribe(
        AudioRecording(
          path: await writeWav(),
          duration: const Duration(seconds: 1),
        ),
      );

      expect(transcript, 'closed late');
    });

    test('shutdown kills the server process', () async {
      final transport = FakeTransport(response: '{"text": "x"}');
      final engine = buildEngine(transport);
      await engine.prepare();

      await engine.shutdown();

      expect(transport.startedProcesses.single.killed, isTrue);
    });
  });
}

ParakeetServerSttEngine buildEngine(
  FakeTransport transport, {
  Duration startupTimeout = const Duration(seconds: 5),
  Duration socketCloseTimeout = const Duration(seconds: 5),
}) {
  return ParakeetServerSttEngine(
    serverExecutable: 'sherpa-server.exe',
    encoderPath: 'encoder.onnx',
    decoderPath: 'decoder.onnx',
    joinerPath: 'joiner.onnx',
    tokensPath: 'tokens.txt',
    startupTimeout: startupTimeout,
    socketCloseTimeout: socketCloseTimeout,
    processStarter: transport.startProcess,
    webSocketConnector: transport.connect,
  );
}

class FakeTransport {
  FakeTransport({
    required this.response,
    this.alreadyRunning = false,
    this.serverEverStarts = true,
    this.closeHangs = false,
  });

  final String response;

  /// Simulates an orphaned server from a previous run that is already
  /// reachable before this engine starts anything.
  final bool alreadyRunning;
  final bool serverEverStarts;

  /// Simulates a wedged server whose close handshake never completes.
  final bool closeHangs;

  final startedProcesses = <FakeProcess>[];
  final startedArguments = <List<String>>[];

  Future<Process> startProcess(
    String executable,
    List<String> arguments,
  ) async {
    final process = FakeProcess();
    startedProcesses.add(process);
    startedArguments.add(arguments);
    return process;
  }

  Future<SttServerSocket> connect(String url) async {
    final reachable =
        alreadyRunning || (startedProcesses.isNotEmpty && serverEverStarts);
    if (!reachable) {
      throw const SocketException('connection refused');
    }
    return FakeSocket(response, closeHangs: closeHangs);
  }
}

class FakeSocket implements SttServerSocket {
  FakeSocket(this.response, {this.closeHangs = false});

  final String response;
  final bool closeHangs;
  // Single-subscription so the response emitted by add() is buffered until
  // the engine subscribes, like a real socket's OS-level buffering.
  final _controller = StreamController<dynamic>();

  @override
  void add(List<int> data) {
    _controller.add(response);
  }

  @override
  Stream<dynamic> get messages => _controller.stream;

  @override
  Future<void> close() async {
    if (closeHangs) {
      return Completer<void>().future;
    }
    // Not awaited: a single-subscription controller's close() only completes
    // once a listener drains it, and probe sockets are never listened to.
    unawaited(_controller.close());
  }
}

class FakeProcess implements Process {
  bool killed = false;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List buildTestWav({required int sampleRate, required List<int> samples}) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  void writeAscii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}
