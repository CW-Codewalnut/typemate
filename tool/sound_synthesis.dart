// Shared audio helpers for the sound-generator tools
// (generate_start_sound.dart, generate_failure_tone.dart): one WAV
// encoder so the container logic is never repeated per sound.
import 'dart:typed_data';

/// Encodes mono 16-bit PCM samples as a RIFF/WAVE file.
Uint8List buildPcm16Wav(Int16List samples, {required int sampleRate}) {
  const bytesPerSample = 2;
  final dataLength = samples.length * bytesPerSample;
  final bytes = BytesBuilder();
  void writeString(String value) => bytes.add(value.codeUnits);
  void writeUint32(int value) => bytes.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
  );
  void writeUint16(int value) => bytes.add(
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little),
  );

  writeString('RIFF');
  writeUint32(36 + dataLength);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1); // PCM
  writeUint16(1); // mono
  writeUint32(sampleRate);
  writeUint32(sampleRate * bytesPerSample);
  writeUint16(bytesPerSample);
  writeUint16(16);
  writeString('data');
  writeUint32(dataLength);
  bytes.add(samples.buffer.asUint8List());
  return bytes.toBytes();
}
