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
///
/// PINNED to a commit revision, never a branch: content at a commit is
/// immutable, so a resume can never append bytes of a newer upload onto
/// an older partial file, and we ship exactly the bytes that were
/// validated — not whatever `main` points at later. The byte sizes come
/// from the same revision and gate the rename-to-complete.
const _parakeetModelRevision = '2bda32ec70b097a55adaa07d9a7173915b43cc78';
const _parakeetModelBaseUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/$_parakeetModelRevision';

const _parakeetModelFileSizes = {
  'encoder.int8.onnx': 652184281,
  'decoder.int8.onnx': 11845275,
  'joiner.int8.onnx': 6355277,
  'tokens.txt': 93939,
};

final parakeetAndroidModelFiles = [
  for (final name in sherpaParakeetModelFileNames)
    SttModelFile(
      url: '$_parakeetModelBaseUrl/$name',
      relativePath: name,
      expectedBytes: _parakeetModelFileSizes[name]!,
    ),
];

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
    ),
  );
}
