// Generates the dictation start chime shipped as a Flutter asset
// (assets/sounds/dictation_start.wav). Run after any tweak to the sound
// design:
//
//   dart tool/generate_start_sound.dart
//
// A calm rising two-tone blip; tool/generate_failure_tone.dart produces
// its falling inverse so start and failure are distinguishable by ear.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'sound_synthesis.dart';

const sampleRate = 22050;
const durationMs = 180;

Int16List synthesizeChime() {
  // A calm two-tone blip (E5 + A5), fast attack, exponential decay. Peak
  // level stays low so the cue never startles in a quiet room.
  final sampleCount = (sampleRate * durationMs / 1000).round();
  final samples = Int16List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final attack = math.min(1.0, t / 0.005);
    final decay = math.exp(-t / 0.045);
    final tone =
        0.8 * math.sin(2 * math.pi * 660 * t) +
        0.35 * math.sin(2 * math.pi * 880 * t);
    final value = 0.30 * attack * decay * tone;
    samples[i] = (value.clamp(-1.0, 1.0) * 32767).round();
  }
  return samples;
}

void main() {
  final wav = buildPcm16Wav(synthesizeChime(), sampleRate: sampleRate);
  final file = File('assets/sounds/dictation_start.wav')
    ..parent.createSync(recursive: true);
  file.writeAsBytesSync(wav, flush: true);
  stdout.writeln('wrote ${file.path} (${wav.length} bytes)');
}
