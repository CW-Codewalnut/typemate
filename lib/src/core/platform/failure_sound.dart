import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Plays the bundled failure tone (assets/sounds/dictation_failed.wav — a
/// falling two-tone, the audible inverse of the rising start chime) so a
/// failed dictation is heard even when the user is not looking at the
/// screen. One Dart implementation for every desktop: Windows through
/// winmm's PlaySound (FFI), macOS through the built-in afplay, Linux
/// through paplay/aplay. No native runner code involved.
typedef FailureSoundPlayer = Future<void> Function();

const failureToneAssetPath = 'assets/sounds/dictation_failed.wav';

typedef _PlaySoundNative = Int32 Function(Pointer<Utf16>, IntPtr, Uint32);
typedef _PlaySoundDart = int Function(Pointer<Utf16>, int, int);

const _sndAsync = 0x0001;
const _sndNoDefault = 0x0002;
const _sndFilename = 0x00020000;

String? _toneFilePath;

// Allocated once and kept: PlaySound(SND_ASYNC) may read the string after
// the call returns, so it must outlive playback.
Pointer<Utf16>? _tonePathUtf16;

Future<void> playDictationFailureSound() async {
  try {
    final path = _toneFilePath ??= await _materializeToneAsset();
    if (Platform.isWindows) {
      _playWindows(path);
    } else if (Platform.isMacOS) {
      unawaited(Process.run('afplay', [path]));
    } else if (Platform.isLinux) {
      unawaited(_playLinux(path));
    }
  } catch (_) {
    // The sound is a garnish; it must never break the failure flow.
  }
}

/// The system players need a real file path, so the bundled asset is
/// written to the temp directory once per run.
Future<String> _materializeToneAsset() async {
  final data = await rootBundle.load(failureToneAssetPath);
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}typemate-dictation-failed.wav',
  );
  file.writeAsBytesSync(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

void _playWindows(String path) {
  final winmm = DynamicLibrary.open('winmm.dll');
  final playSound = winmm.lookupFunction<_PlaySoundNative, _PlaySoundDart>(
    'PlaySoundW',
  );
  _tonePathUtf16 ??= path.toNativeUtf16();
  playSound(_tonePathUtf16!, 0, _sndFilename | _sndAsync | _sndNoDefault);
}

Future<void> _playLinux(String path) async {
  // PipeWire/Pulse desktops ship paplay; aplay covers bare ALSA setups.
  for (final command in [
    ['paplay', path],
    ['aplay', '-q', path],
  ]) {
    try {
      final result = await Process.run(command.first, command.sublist(1));
      if (result.exitCode == 0) {
        return;
      }
    } catch (_) {
      // Try the next player.
    }
  }
}
