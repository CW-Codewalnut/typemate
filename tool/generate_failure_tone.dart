// Generates the dictation-failure tone shipped as a Flutter asset
// (assets/sounds/dictation_failed.wav). Run after any tweak to the sound
// design:
//
//   dart tool/generate_failure_tone.dart
//
// The tone is a soft descending 660Hz -> 440Hz pair — the falling inverse
// of the rising start chime (tool/generate_start_sound.dart), so success
// and failure are distinguishable by ear alone.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'sound_synthesis.dart';

const sampleRate = 16000;

Int16List synthesizeFailureTone() {
  final samples = <int>[];
  void tone(double frequency, int milliseconds) {
    // Low gain and edge fades: an alert, not a startle.
    const gain = 0.28;
    final count = sampleRate * milliseconds ~/ 1000;
    for (var i = 0; i < count; i++) {
      final fadeIn = math.min(1.0, i / 200);
      final fadeOut = math.min(1.0, (count - i) / 400);
      final value =
          gain *
          fadeIn *
          fadeOut *
          math.sin(2 * math.pi * frequency * i / sampleRate);
      samples.add((value * 32767).round());
    }
  }

  tone(660, 150);
  samples.addAll(List.filled(sampleRate * 40 ~/ 1000, 0));
  tone(440, 240);
  return Int16List.fromList(samples);
}

void main() {
  final wav = buildPcm16Wav(synthesizeFailureTone(), sampleRate: sampleRate);
  final file = File('assets/sounds/dictation_failed.wav')
    ..parent.createSync(recursive: true);
  file.writeAsBytesSync(wav, flush: true);
  stdout.writeln('wrote ${file.path} (${wav.length} bytes)');
}
