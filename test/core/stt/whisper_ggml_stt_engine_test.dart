import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart'
    show SttRuntimeException;
import 'package:typemate/src/core/stt/whisper_ggml_stt_engine.dart';

void main() {
  final recording = AudioRecording(
    path: 'clip.wav',
    duration: const Duration(seconds: 3),
  );

  WhisperGgmlSttEngine engine({
    required Future<String> Function(String payload) requestRunner,
    String? prompt,
    bool modelExists = true,
  }) {
    return WhisperGgmlSttEngine(
      modelPath: 'models/ggml-test.bin',
      language: 'hi',
      vadModelPath: 'models/vad.bin',
      prompt: prompt,
      modelFileExists: (_) => modelExists,
      requestRunner: requestRunner,
    );
  }

  String okResponse(String text) =>
      json.encode({'@type': 'transcribe', 'text': text});

  test('transcribe sends the corpus-locked decode settings', () async {
    Map<String, dynamic>? sent;
    final result = await engine(
      requestRunner: (payload) async {
        sent = json.decode(payload) as Map<String, dynamic>;
        return okResponse('नमस्ते');
      },
    ).transcribe(recording);

    expect(result, 'नमस्ते');
    expect(sent!['@type'], 'getTextFromWavFile');
    expect(sent!['audio'], 'clip.wav');
    expect(sent!['model'], 'models/ggml-test.bin');
    expect(sent!['language'], 'hi');
    // Greedy decoding only: temperature fallback slowed Tamil 50%+ for no
    // quality change.
    expect(sent!['no_fallback'], isTrue);
    // Prior-segment context invites repetition on short utterances.
    expect(sent!['no_context'], isTrue);
    // The resident-model patch: one load, warm forever.
    expect(sent!['keep_model_loaded'], isTrue);
    expect(sent!['vad_model'], 'models/vad.bin');
    expect(sent!['vad_speech_pad_ms'], 100);
    // The fine-tunes carry their scripts natively; a prompt bleeds its
    // own characters into the transcript.
    expect(sent!['initial_prompt'], isNull);
  });

  test('an explicit prompt is passed through when configured', () async {
    Map<String, dynamic>? sent;
    await engine(
      prompt: 'लिपि',
      requestRunner: (payload) async {
        sent = json.decode(payload) as Map<String, dynamic>;
        return okResponse('ठीक');
      },
    ).transcribe(recording);

    expect(sent!['initial_prompt'], 'लिपि');
  });

  test('cleans replacement characters and collapses whitespace', () async {
    final result = await engine(
      requestRunner: (_) async =>
          okResponse('  पहला\u{FFFD}शब्द \n  दूसरा   तीसरा \n'),
    ).transcribe(recording);

    expect(result, 'पहला शब्द दूसरा तीसरा');
  });

  test('a native error response surfaces as SttRuntimeException', () {
    final failing = engine(
      requestRunner: (_) async => json.encode({
        '@type': 'error',
        'message': 'failed to load model models/ggml-test.bin',
      }),
    );

    expect(
      () => failing.transcribe(recording),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('failed to load model'),
        ),
      ),
    );
  });

  test('a missing model refuses before any native call', () async {
    var requests = 0;
    final missing = engine(
      modelExists: false,
      requestRunner: (_) async {
        requests++;
        return okResponse('never');
      },
    );

    await expectLater(
      () => missing.transcribe(recording),
      throwsA(
        isA<SttRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('not downloaded'),
        ),
      ),
    );
    await expectLater(missing.prepare, throwsA(isA<SttRuntimeException>()));
    expect(requests, 0);
  });

  test('prepare warms once with a silence clip, then no-ops', () async {
    final audioPaths = <String>[];
    final warm = engine(
      requestRunner: (payload) async {
        final sent = json.decode(payload) as Map<String, dynamic>;
        audioPaths.add(sent['audio'] as String);
        // The warm-up clip must exist at request time (it is deleted
        // right after).
        expect(File(sent['audio'] as String).existsSync(), isTrue);
        return okResponse('');
      },
    );

    expect(await warm.isReady(), isFalse);
    await warm.prepare();
    await warm.prepare();

    expect(await warm.isReady(), isTrue);
    expect(audioPaths, hasLength(1));
    expect(audioPaths.single, endsWith('.wav'));
    expect(File(audioPaths.single).existsSync(), isFalse);
  });

  test('shutdown releases the resident model only when warm', () async {
    final types = <String>[];
    final e = engine(
      requestRunner: (payload) async {
        final sent = json.decode(payload) as Map<String, dynamic>;
        types.add(sent['@type'] as String);
        return okResponse('text');
      },
    );

    // Cold: nothing to release, no native call.
    await e.shutdown();
    expect(types, isEmpty);

    await e.transcribe(recording);
    await e.shutdown();

    expect(types, ['getTextFromWavFile', 'releaseModel']);
    expect(await e.isReady(), isFalse);
  });
}
