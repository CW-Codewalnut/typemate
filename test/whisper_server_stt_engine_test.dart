import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/diagnostics/diagnostic_log.dart';
import 'package:typemate/src/core/diagnostics/diagnostic_reporter.dart';
import 'package:typemate/src/core/stt/whisper_server_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttRuntimeException;

class _RecordingTelemetrySink implements TelemetrySink {
  final calls = <(String, String, String)>[];

  @override
  void reportFailure(String area, String kind, String message) {
    calls.add((area, kind, message));
  }
}

void main() {
  const recording = AudioRecording(
    path: 'clip.wav',
    duration: Duration(seconds: 8),
  );

  test('starts the server once with model, language, and VAD', () async {
    final transport = FakeHttpTransport(response: '{"text": "नमस्ते"}');
    final engine = buildEngine(transport);

    final transcript = await engine.transcribe(recording);

    expect(transcript, 'नमस्ते');
    expect(transport.startedProcesses, hasLength(1));
    final arguments = transport.startedArguments.single.join(' ');
    expect(arguments, contains('-m models/hindi.bin'));
    expect(arguments, contains('--port 43008'));
    expect(arguments, contains('-l hi'));
    expect(arguments, contains('--beam-size 1'));
    expect(arguments, contains('--vad-model models/vad.bin'));
    expect(arguments, contains('--vad-speech-pad-ms 100'));

    // Second transcription reuses the running server.
    await engine.transcribe(recording);
    expect(transport.startedProcesses, hasLength(1));
  });

  test('sends per-request fields: json, audio_ctx, and the prompt', () async {
    final transport = FakeHttpTransport(response: '{"text": "x"}');
    final engine = buildEngine(transport, prompt: 'देवनागरी में लिखें');

    await engine.transcribe(recording);

    final fields = transport.requestFields.single;
    expect(fields['response_format'], 'json');
    expect(fields['temperature'], '0.0');
    // 8s clip + 2s margin = 10/30 of the window -> 500 frames.
    expect(fields['audio_ctx'], '500');
    expect(fields['prompt'], 'देवनागरी में लिखें');
    expect(transport.requestPaths.single, 'clip.wav');
  });

  test(
    'omits audio_ctx when duration is unknown and prompt when unset',
    () async {
      final transport = FakeHttpTransport(response: '{"text": "x"}');
      final engine = buildEngine(transport);

      await engine.transcribe(
        const AudioRecording(path: 'clip.wav', duration: Duration.zero),
      );

      final fields = transport.requestFields.single;
      expect(fields.containsKey('audio_ctx'), isFalse);
      expect(fields.containsKey('prompt'), isFalse);
    },
  );

  test('cleans replacement characters and wrapped lines from output', () async {
    final transport = FakeHttpTransport(
      response: '{"text": "\u{FFFD} आज मौसम\\nअच्छा है\\n"}',
    );
    final engine = buildEngine(transport);

    expect(await engine.transcribe(recording), 'आज मौसम अच्छा है');
  });

  test(
    'adopts an already-running server instead of starting another',
    () async {
      final transport = FakeHttpTransport(
        response: '{"text": "adopted"}',
        alreadyRunning: true,
      );
      final engine = buildEngine(transport);

      expect(await engine.transcribe(recording), 'adopted');
      expect(transport.startedProcesses, isEmpty);
    },
  );

  test(
    'throws a clear error when the server never becomes reachable',
    () async {
      final transport = FakeHttpTransport(
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
            contains('speech server'),
          ),
        ),
      );
    },
  );

  test('reports a startup timeout with the server stderr tail', () async {
    final temp = await Directory.systemTemp.createTemp('whisper-diag-test');
    addTearDown(() async => temp.delete(recursive: true));
    final logFile = File('${temp.path}/typemate.log');
    final sink = _RecordingTelemetrySink();
    final transport = FakeHttpTransport(
      response: '{"text": "x"}',
      serverEverStarts: false,
      stderrText: 'whisper_init: failed to load model',
    );
    final engine = buildEngine(
      transport,
      startupTimeout: const Duration(milliseconds: 50),
      diagnostics: DiagnosticReporter(
        log: DiagnosticLog(file: logFile),
        telemetrySink: sink,
      ),
    );

    await expectLater(engine.prepare(), throwsA(isA<SttRuntimeException>()));

    final content = logFile.readAsStringSync();
    expect(content, contains('[stt] starting whisper server for "hi"'));
    expect(content, contains('whisper-start-timeout'));
    expect(content, contains('whisper_init: failed to load model'));
    expect(sink.calls.single.$2, 'whisper-start-timeout');
  });

  test('shutdown kills the server process', () async {
    final transport = FakeHttpTransport(response: '{"text": "x"}');
    final engine = buildEngine(transport);
    await engine.prepare();

    await engine.shutdown();

    expect(transport.startedProcesses.single.killed, isTrue);
  });

  test('times out when the server sends headers but the body stalls', () async {
    // A real server that answers with headers and then never finishes the
    // body — the exact shape of a wedged whisper-server mid-decode.
    final stallingServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => stallingServer.close(force: true));
    stallingServer.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.headers.contentLength = 1024;
      request.response.write('{');
      await request.response.flush();
      // Never close: the body stays incomplete forever.
    });

    final temp = await Directory.systemTemp.createTemp('whisper-server-test');
    addTearDown(() async => temp.delete(recursive: true));
    final clip = File('${temp.path}/clip.wav');
    await clip.writeAsBytes(const [1, 2, 3]);

    final engine = WhisperServerSttEngine(
      serverExecutable: 'unused',
      modelPath: 'unused',
      vadModelPath: 'unused',
      cliLanguage: 'hi',
      port: stallingServer.port,
      bodyReadTimeout: const Duration(milliseconds: 200),
      processStarter: (_, _) async => throw StateError('must not start'),
      connectionProbe: (_) async => true,
    );

    await expectLater(
      engine.transcribe(
        AudioRecording(path: clip.path, duration: const Duration(seconds: 1)),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}

WhisperServerSttEngine buildEngine(
  FakeHttpTransport transport, {
  String? prompt,
  Duration startupTimeout = const Duration(seconds: 5),
  DiagnosticReporter? diagnostics,
}) {
  return WhisperServerSttEngine(
    serverExecutable: 'bin/whisper/whisper-server.exe',
    modelPath: 'models/hindi.bin',
    vadModelPath: 'models/vad.bin',
    cliLanguage: 'hi',
    port: 43008,
    prompt: prompt,
    startupTimeout: startupTimeout,
    diagnostics: diagnostics,
    processStarter: transport.startProcess,
    connectionProbe: transport.probe,
    inferenceClient: transport.infer,
  );
}

class FakeHttpTransport {
  FakeHttpTransport({
    required this.response,
    this.alreadyRunning = false,
    this.serverEverStarts = true,
    this.stderrText,
  });

  final String response;
  final bool alreadyRunning;
  final bool serverEverStarts;

  /// Emitted as the spawned server's stderr, for diagnostics assertions.
  final String? stderrText;

  final startedProcesses = <FakeServerProcess>[];
  final startedArguments = <List<String>>[];
  final requestFields = <Map<String, String>>[];
  final requestPaths = <String>[];

  Future<Process> startProcess(
    String executable,
    List<String> arguments,
  ) async {
    final process = FakeServerProcess(stderrText: stderrText);
    startedProcesses.add(process);
    startedArguments.add(arguments);
    return process;
  }

  Future<bool> probe(int port) async =>
      alreadyRunning || (startedProcesses.isNotEmpty && serverEverStarts);

  Future<String> infer(
    Uri url,
    String audioFilePath,
    Map<String, String> fields,
  ) async {
    requestPaths.add(audioFilePath);
    requestFields.add(fields);
    return response;
  }
}

class FakeServerProcess implements Process {
  FakeServerProcess({this.stderrText});

  bool killed = false;
  final String? stderrText;
  final _exitCode = Completer<int>();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => stderrText == null
      ? const Stream.empty()
      : Stream.value(utf8.encode(stderrText!));

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exitCode.isCompleted) {
      _exitCode.complete(-1);
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
