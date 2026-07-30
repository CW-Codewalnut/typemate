import 'dart:io';

import '../diagnostics/diagnostic_reporter.dart';
import 'sherpa_parakeet_stt_engine.dart';
import 'stt_model_provisioner.dart';

/// Same model directory name the desktop bundle uses, so tooling and docs
/// talk about one model identity everywhere.
const parakeetAndroidModelDirectoryName = 'parakeet-tdt-0.6b-v3-int8';

/// The official sherpa-onnx export of NVIDIA Parakeet TDT 0.6B v3 int8 —
/// byte-for-byte the model the desktop resident server loads. Individual
/// files (not the .tar.bz2 archive) so the download streams straight to
/// disk with HTTP-range resume and no on-phone archive extraction.
const _parakeetModelBaseUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main';

final parakeetAndroidModelFiles = [
  for (final name in sherpaParakeetModelFileNames)
    SttModelFile(url: '$_parakeetModelBaseUrl/$name', relativePath: name),
];

/// Approximate on-disk size (encoder 622 MB + decoder 12 MB + joiner 6 MB
/// + tokens); drives the progress fraction and the size shown to the user.
const parakeetAndroidModelTotalBytes = 671000000;

/// The Android speech stack: the on-device Parakeet engine plus the
/// first-run downloader for its model files. Both point at the same
/// directory under the app's private data directory.
({SherpaParakeetSttEngine engine, SttModelProvisioner provisioner})
createAndroidSpeechRuntime({
  required Directory dataDirectory,
  DiagnosticReporter? diagnostics,
}) {
  final modelDirectory = Directory(
    '${dataDirectory.path}/models/$parakeetAndroidModelDirectoryName',
  );
  return (
    engine: SherpaParakeetSttEngine(
      modelDirectoryPath: modelDirectory.path,
      diagnostics: diagnostics,
    ),
    provisioner: SttModelProvisioner(
      modelDirectory: modelDirectory,
      files: parakeetAndroidModelFiles,
      expectedTotalBytes: parakeetAndroidModelTotalBytes,
    ),
  );
}
