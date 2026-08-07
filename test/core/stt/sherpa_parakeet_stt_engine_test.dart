import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/sherpa_parakeet_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttRuntimeException;

/// A worker that answers the real protocol without sherpa. It reports each
/// step over [SherpaWorkerInit.modelDirectoryPath], reused as a send-port
/// address, so the test sees the order the engine actually drives.
///
/// Stands in for the production entrypoint, which loads 654 MB of weights
/// over FFI and cannot run in a unit test — so injecting it is the only way
/// to exercise the engine's own lifecycle rather than a hand-written mock
/// of it.
void fakeWorker(SherpaWorkerInit init) {
  final events = IsolateNameServer.lookupPortByName(init.modelDirectoryPath);
  final commands = ReceivePort();
  init.readyPort.send(commands.sendPort);
  commands.listen((message) {
    if (message is SherpaTranscribeRequest) {
      message.replyPort.send('fake transcript');
      return;
    }
    if (message is SherpaShutdownRequest) {
      // Stands in for recognizer.free(): the engine must not kill us
      // before this runs, or the model's native memory is never released.
      events?.send('freed');
      message.freedPort.send(null);
      commands.close();
    }
  });
}

/// A worker that accepts the shutdown request and never acknowledges it,
/// so the engine has to fall back to killing it.
void wedgedWorker(SherpaWorkerInit init) {
  final commands = ReceivePort();
  init.readyPort.send(commands.sendPort);
  commands.listen((_) {});
}

/// A worker that dies as soon as it is asked to transcribe.
void dyingWorker(SherpaWorkerInit init) {
  final commands = ReceivePort();
  init.readyPort.send(commands.sendPort);
  commands.listen((message) {
    if (message is SherpaTranscribeRequest) {
      commands.close();
      Isolate.current.kill(priority: Isolate.immediate);
    }
  });
}

void main() {
  /// The engine checks for real model files before spawning anything.
  Directory stubModelDirectory() {
    final directory = Directory.systemTemp.createTempSync('typemate-sherpa');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final name in sherpaParakeetModelFileNames) {
      File('${directory.path}/$name').writeAsStringSync('stub');
    }
    return directory;
  }

  test('prepare fails fast when a model file is missing', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-sherpa');
    addTearDown(() => directory.deleteSync(recursive: true));
    // Everything present except the encoder: the guard must catch it
    // before any isolate or FFI work starts.
    for (final name in sherpaParakeetModelFileNames.skip(1)) {
      File('${directory.path}/$name').writeAsStringSync('stub');
    }
    final engine = SherpaParakeetSttEngine(modelDirectoryPath: directory.path);

    await expectLater(
      engine.prepare(),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.toString(),
          'message',
          contains('encoder.int8.onnx'),
        ),
      ),
    );
    expect(await engine.isReady(), isFalse);

    // A later attempt is allowed to retry (and fails the same way rather
    // than being stuck behind a cached in-flight prepare).
    await expectLater(engine.prepare(), throwsA(isA<SttRuntimeException>()));
  });

  test('shutdown on an engine that never started is a no-op', () async {
    final engine = SherpaParakeetSttEngine(modelDirectoryPath: '/nonexistent');

    await expectLater(engine.shutdown(), completes);
    expect(await engine.isReady(), isFalse);
  });

  test('shutdown lets the worker free the model before killing it', () async {
    // shutdown() used to send the request and kill on the next line, which
    // usually preempted recognizer.free() and left the model's native
    // memory allocated across a language switch. Driving the real engine:
    // the freed signal must arrive before shutdown() returns, every time.
    final directory = stubModelDirectory();
    final events = ReceivePort();
    final channelName = directory.path;
    IsolateNameServer.registerPortWithName(events.sendPort, channelName);
    addTearDown(() {
      IsolateNameServer.removePortNameMapping(channelName);
      events.close();
    });
    final freed = <String>[];
    events.listen((event) => freed.add(event as String));

    for (var cycle = 0; cycle < 10; cycle++) {
      final engine = SherpaParakeetSttEngine(
        modelDirectoryPath: directory.path,
        workerEntryPoint: fakeWorker,
      );
      await engine.prepare();
      expect(await engine.isReady(), isTrue);

      await engine.shutdown();
      // The port delivers asynchronously; one turn is enough because the
      // ack the engine already awaited is sent after the freed signal.
      await Future<void>.delayed(Duration.zero);

      expect(
        freed.length,
        cycle + 1,
        reason: 'the model was not freed on cycle $cycle',
      );
      expect(await engine.isReady(), isFalse);
    }
  });

  test('shutdown gives up on a worker that never acknowledges', () async {
    // The kill is the backstop: a wedged worker must not hang shutdown
    // forever, and the engine must still end up unloaded.
    final engine = SherpaParakeetSttEngine(
      modelDirectoryPath: stubModelDirectory().path,
      workerEntryPoint: wedgedWorker,
    );
    await engine.prepare();

    await expectLater(
      engine.shutdown().timeout(SherpaParakeetSttEngine.shutdownAckTimeout * 2),
      completes,
    );
    expect(await engine.isReady(), isFalse);
  });

  test('a worker that dies mid-decode fails rather than hanging', () async {
    // transcribe() used to await the reply with no death port, so a worker
    // lost mid-decode left the future pending forever — and the handles
    // still looked alive, so every later dictation hung the same way.
    final directory = stubModelDirectory();
    final engine = SherpaParakeetSttEngine(
      modelDirectoryPath: directory.path,
      workerEntryPoint: dyingWorker,
    );
    await engine.prepare();

    await expectLater(
      engine
          .transcribe(
            const AudioRecording(path: 'clip.wav', duration: Duration.zero),
          )
          .timeout(const Duration(seconds: 10)),
      throwsA(isA<SttRuntimeException>()),
    );

    // The dead worker must be forgotten, not left looking ready.
    await Future<void>.delayed(Duration.zero);
    expect(await engine.isReady(), isFalse);
  });
}
