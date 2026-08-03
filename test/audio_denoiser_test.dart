import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';

/// The success path (real GTCRN inference through the sherpa_onnx plugin)
/// needs the native library next to the executable, which only the real
/// app has; it is verified live. These tests pin the failure contract:
/// the denoiser never throws and never loses the recording.
void main() {
  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('typemate-denoise');
  });

  tearDown(() {
    tempDirectory.deleteSync(recursive: true);
  });

  File writeRecordingFile() =>
      File('${tempDirectory.path}/clip.wav')..writeAsStringSync('raw-audio');

  AudioRecording recordingFor(File file) =>
      AudioRecording(path: file.path, duration: const Duration(seconds: 3));

  test('keeps the raw recording when denoising fails', () async {
    // The test runner has no sherpa native library (and no real model), so
    // the in-isolate denoise throws — exactly the failure the contract
    // covers: the original recording must come back untouched.
    final file = writeRecordingFile();
    final denoiser = SherpaGtcrnAudioDenoiser(
      modelPath: '${tempDirectory.path}/missing-gtcrn.onnx',
    );

    final result = await denoiser.denoise(recordingFor(file));

    expect(result.path, file.path);
    expect(result.duration, const Duration(seconds: 3));
    expect(file.readAsStringSync(), 'raw-audio');
    expect(File('${file.path}.denoised.wav').existsSync(), isFalse);
  });

  test('skips empty recordings without touching the filesystem', () async {
    final denoiser = SherpaGtcrnAudioDenoiser(modelPath: 'model');

    final result = await denoiser.denoise(
      const AudioRecording(path: '', duration: Duration.zero),
    );

    expect(result.path, '');
  });
}
