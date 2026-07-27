import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled failure tone is a valid 16kHz mono PCM16 WAV with audio', () {
    // The checked-in asset (regenerate: dart tool/generate_failure_tone.dart)
    // is what ships and what every platform's player receives.
    final wav = File('assets/sounds/dictation_failed.wav').readAsBytesSync();
    final data = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
    expect(data.getUint32(24, Endian.little), 16000, reason: 'sample rate');
    expect(data.getUint16(34, Endian.little), 16, reason: 'bits per sample');
    // Declared data size matches the file and is non-trivial (~430ms).
    final dataSize = data.getUint32(40, Endian.little);
    expect(wav.length, 44 + dataSize);
    expect(dataSize, greaterThan(16000 ~/ 2));
    // It actually contains sound, not silence.
    var peak = 0;
    for (var offset = 44; offset + 1 < wav.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little).abs();
      if (sample > peak) {
        peak = sample;
      }
    }
    expect(peak, greaterThan(2000));
  });
}
