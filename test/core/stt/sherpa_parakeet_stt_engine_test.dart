import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/stt/sherpa_parakeet_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttRuntimeException;

/// Mirrors the engine's worker loop without sherpa: releases its "native"
/// resource, then acknowledges. The real worker cannot be driven from a
/// unit test (it loads a 654 MB model over FFI), so the shutdown contract
/// is pinned on an isolate shaped the same way.
void _probeWorker(SendPort readyPort) {
  final commands = ReceivePort();
  readyPort.send(commands.sendPort);
  commands.listen((message) {
    final ports = message as List;
    final freedPort = ports[0] as SendPort;
    // Stands in for recognizer.free(); the ack must follow it, never
    // precede it.
    freedPort.send('freed');
    commands.close();
  });
}

void main() {
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

  test('waiting for the shutdown ack always lets cleanup run', () async {
    // shutdown() used to send the request and kill the isolate straight
    // after, which usually preempted recognizer.free() and left the
    // model's native memory allocated across a language switch. Killing
    // only after the worker acknowledges makes cleanup deterministic —
    // asserted over repeated cycles because the old shape failed
    // intermittently, roughly half the time.
    for (var cycle = 0; cycle < 20; cycle++) {
      final readyPort = ReceivePort();
      final isolate = await Isolate.spawn(_probeWorker, readyPort.sendPort);
      final commands = await readyPort.first as SendPort;
      readyPort.close();

      final freedPort = ReceivePort();
      commands.send([freedPort.sendPort]);
      final freed = await freedPort.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'timed out',
      );
      freedPort.close();
      isolate.kill(priority: Isolate.beforeNextEvent);

      expect(freed, 'freed', reason: 'cleanup must run on cycle $cycle');
    }
  });
}
