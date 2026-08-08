import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/audio_denoiser.dart';

/// The reported crash, end to end, against the real GTCRN model.
///
/// The unit tests cover the decision and prove the native call is not made,
/// but they cannot cover the two lines inside `_denoiseInPlace` that wire
/// the real `readWave` and the real FFI call into it. This can: noise
/// suppression aborts the PROCESS on degenerate audio, so if that wiring
/// ever regresses this test does not fail an expectation — the test runner
/// loses the app, which is exactly the failure users saw.
///
/// GTCRN is ~0.5 MB and bundled, so nothing is downloaded here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Windows and Linux are the only targets whose build fetches GTCRN.
  // Android never bundles it — it rides a Parakeet download CI does not
  // perform — and the macOS build has no fetch step and runs e2e on
  // flutter-tester, which cannot load the sherpa dylib at all.
  //
  // Skipped rather than returned early: an early return registers no tests
  // at all, and the runner treats a file with nothing in it as a failure
  // ("No tests were found", exit 79). This gate is on the PLATFORM only —
  // where the model is expected, its absence still fails loudly below,
  // because a skip-when-missing would let this pass by doing nothing on
  // exactly the platforms it exists for.
  final unsupportedPlatform = !Platform.isWindows && !Platform.isLinux;

  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('typemate-denoise-e2e');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  /// The bundled half of production's search: next to the working
  /// directory, then next to the executable. Production has a third step —
  /// falling back to a downloaded copy under the data directory — which is
  /// deliberately not repeated here, because on these two platforms a
  /// bundled model is exactly what must be present.
  String? bundledGtcrn() {
    final directories = [
      Directory.current.path.replaceAll('\\', '/'),
      File(Platform.resolvedExecutable).parent.path.replaceAll('\\', '/'),
    ];
    for (final directory in directories) {
      final path = '$directory/models/gtcrn_simple.onnx';
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  File writeWav(
    String name, {
    required int sampleCount,
    int sampleRate = 16000,
  }) {
    const headerBytes = 44;
    final dataBytes = sampleCount * 2;
    final bytes = BytesBuilder();
    final header = ByteData(headerBytes);
    header
      ..setUint32(0, 0x52494646) // 'RIFF'
      ..setUint32(4, 36 + dataBytes, Endian.little)
      ..setUint32(8, 0x57415645) // 'WAVE'
      ..setUint32(12, 0x666d7420) // 'fmt '
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // 'data'
      ..setUint32(40, dataBytes, Endian.little);
    bytes.add(header.buffer.asUint8List());

    // Deterministic noise: the denoiser has to have something to remove,
    // so that a real run visibly changes the file.
    final random = Random(7);
    final samples = ByteData(dataBytes);
    for (var i = 0; i < sampleCount; i++) {
      samples.setInt16(i * 2, random.nextInt(12000) - 6000, Endian.little);
    }
    bytes.add(samples.buffer.asUint8List());

    return File('${workspace.path}/$name')..writeAsBytesSync(bytes.toBytes());
  }

  AudioRecording recordingFor(File file) =>
      AudioRecording(path: file.path, duration: const Duration(seconds: 1));

  testWidgets('degenerate audio cannot kill the app', (tester) async {
    final model = bundledGtcrn();
    // Loud rather than skipped: if the model is not where production looks
    // for it, the app's noise suppression is broken and this test would
    // otherwise pass by doing nothing.
    expect(
      model,
      isNotNull,
      reason: 'models/gtcrn_simple.onnx must be bundled next to the app.',
    );
    final denoiser = SherpaGtcrnAudioDenoiser(modelPathCandidates: [model!]);

    // First prove the native path actually runs HERE. Without this the
    // rest of the test passes on a machine where sherpa never loaded —
    // denoise() swallows every failure and returns the raw recording, so
    // "it did not crash" would be meaningless.
    final speech = writeWav('speech.wav', sampleCount: 16000);
    final before = speech.readAsBytesSync();
    await denoiser.denoise(recordingFor(speech));
    expect(
      speech.readAsBytesSync(),
      isNot(before),
      reason: 'GTCRN did not run, so this test could not detect a crash.',
    );

    // The field report: an unreadable recording. readWave returns sample
    // rate 0, and GTCRN divides by it building a resampler (c0000094).
    final unreadable = File('${workspace.path}/unreadable.wav')
      ..writeAsBytesSync(Uint8List(0));
    final unreadableResult = await denoiser.denoise(recordingFor(unreadable));
    expect(
      unreadableResult.path,
      unreadable.path,
      reason: 'A refused recording falls back to the raw audio.',
    );

    // Zero samples with a valid header: the recognizer's abort case, and
    // the denoiser must not choke on it either.
    final silent = writeWav('silent.wav', sampleCount: 0);
    final silentResult = await denoiser.denoise(recordingFor(silent));
    expect(silentResult.path, silent.path);

    // Still alive, and still working: the point is that the process
    // survived both, so the next dictation is unaffected.
    final again = writeWav('again.wav', sampleCount: 16000);
    final againBefore = again.readAsBytesSync();
    await denoiser.denoise(recordingFor(again));
    expect(
      again.readAsBytesSync(),
      isNot(againBefore),
      reason: 'Noise suppression still works after refusing bad audio.',
    );
  }, skip: unsupportedPlatform);
}
