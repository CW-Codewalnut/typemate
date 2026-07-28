import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/dictation_sounds.dart';

void main() {
  // The checked-in assets are what ship and what every platform's player
  // receives. Regenerate with tool/generate_start_sound.dart and
  // tool/generate_failure_tone.dart.
  void expectValidMonoPcm16Wav(
    String path, {
    required int sampleRate,
    required int minDataBytes,
  }) {
    final wav = File(path).readAsBytesSync();
    final data = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF', reason: path);
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE', reason: path);
    expect(data.getUint16(22, Endian.little), 1, reason: '$path mono');
    expect(
      data.getUint32(24, Endian.little),
      sampleRate,
      reason: '$path sample rate',
    );
    expect(data.getUint16(34, Endian.little), 16, reason: '$path bit depth');
    final dataSize = data.getUint32(40, Endian.little);
    expect(wav.length, 44 + dataSize, reason: path);
    expect(dataSize, greaterThan(minDataBytes), reason: path);
    // It actually contains sound, not silence.
    var peak = 0;
    for (var offset = 44; offset + 1 < wav.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little).abs();
      if (sample > peak) {
        peak = sample;
      }
    }
    expect(peak, greaterThan(2000), reason: '$path must not be silent');
  }

  test('bundled start chime is a valid WAV with audio', () {
    expectValidMonoPcm16Wav(
      'assets/sounds/dictation_start.wav',
      sampleRate: 22050,
      minDataBytes: 2000,
    );
  });

  test('bundled failure tone is a valid WAV with audio', () {
    expectValidMonoPcm16Wav(
      'assets/sounds/dictation_failed.wav',
      sampleRate: 16000,
      minDataBytes: 16000 ~/ 2,
    );
  });

  test('a hung sound player is killed at the timeout', () async {
    // A wedged audio stack must never loop a 200ms cue forever.
    final hangingCommand = Platform.isWindows
        ? ['ping', '-n', '30', '127.0.0.1']
        : ['sleep', '30'];

    final stopwatch = Stopwatch()..start();
    final playedCleanly = await runBoundedSoundPlayer(
      hangingCommand,
      timeout: const Duration(milliseconds: 300),
    );
    stopwatch.stop();

    expect(playedCleanly, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('a well-behaved sound player reports success', () async {
    final quickCommand = Platform.isWindows
        ? ['cmd', '/c', 'echo ok']
        : ['true'];

    expect(await runBoundedSoundPlayer(quickCommand), isTrue);
  });
}
