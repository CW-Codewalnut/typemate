import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/stt/sherpa_parakeet_stt_engine.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttRuntimeException;

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
}
