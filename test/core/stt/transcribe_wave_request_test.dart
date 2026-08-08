import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:typemate/src/core/stt/sherpa_parakeet_stt_engine.dart';

/// What the Parakeet worker does with one transcribe request, without the
/// 654 MB model: `WaveData` is a plain Dart class, so these hand it the
/// exact shapes that abort the process natively.
sherpa_onnx.WaveData wave({
  required int sampleCount,
  required int sampleRate,
}) => sherpa_onnx.WaveData(
  samples: Float32List(sampleCount),
  sampleRate: sampleRate,
);

void main() {
  test('silence is answered as an empty transcript, without decoding', () {
    var decodes = 0;

    final reply = transcribeWaveRequest(
      'clip.wav',
      readWave: (_) => wave(sampleCount: 0, sampleRate: 16000),
      decode: (_) {
        decodes++;
        return 'should never run';
      },
    );

    expect(reply, '');
    expect(
      decodes,
      0,
      reason:
          "Zero samples makes the encoder's first convolution reject an "
          'input shape of {0,128} and abort.',
    );
  });

  test('an unreadable recording is a failure, not silence', () {
    var decodes = 0;

    final reply = transcribeWaveRequest(
      'clip.wav',
      readWave: (_) => wave(sampleCount: 0, sampleRate: 0),
      decode: (_) {
        decodes++;
        return 'should never run';
      },
    );

    expect(reply, isA<SherpaWorkerFailure>());
    expect('$reply', contains('could not be read'));
    expect(decodes, 0);
    expect(
      reply,
      isNot(isA<String>()),
      reason:
          'A lost recording must not come back as an empty transcript: the '
          'user would be told they said nothing.',
    );
  });

  test('real audio is decoded and the transcript returned', () {
    final decoded = <int>[];

    final reply = transcribeWaveRequest(
      'clip.wav',
      readWave: (_) => wave(sampleCount: 32000, sampleRate: 16000),
      decode: (audio) {
        decoded.add(audio.samples.length);
        return 'ship it on friday';
      },
    );

    expect(reply, 'ship it on friday');
    expect(
      decoded,
      [32000],
      reason: 'The wave is read once and handed straight to the recognizer.',
    );
  });

  test('short audio still decodes', () {
    // A 10ms clip is fine against the real recognizer; only zero is fatal.
    final reply = transcribeWaveRequest(
      'clip.wav',
      readWave: (_) => wave(sampleCount: 160, sampleRate: 16000),
      decode: (_) => 'yes',
    );

    expect(reply, 'yes');
  });
}
