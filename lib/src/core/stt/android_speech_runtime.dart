import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import '../diagnostics/diagnostic_reporter.dart';
import 'sherpa_parakeet_stt_engine.dart';
import 'stt_model_provisioner.dart';

/// Same model directory name the desktop bundle uses, so tooling and docs
/// talk about one model identity everywhere.
const parakeetAndroidModelDirectoryName = 'parakeet-tdt-0.6b-v3-int8';

/// The model-download foreground-service notification. `{progress}` is the
/// live percent the package fills in — kept here so a test pins it and it
/// cannot be silently dropped. The title carries no "TypeMate" (Android
/// already shows the app name), and there is no `complete` notification
/// (it fires once per file, stacking four "ready" notifications).
const speechModelDownloadNotification = TaskNotification(
  'Downloading speech model',
  '{progress}',
);

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

/// SHA-256 of each file at the pinned revision (Hugging Face LFS oids;
/// tokens.txt hashed from the revision directly). A corrupt model file
/// aborts the whole process inside the native loader, so content is
/// verified before a download can complete. Update together with the
/// revision and the sizes above.
const _parakeetModelFileHashes = {
  'encoder.int8.onnx':
      'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
  'decoder.int8.onnx':
      '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
  'joiner.int8.onnx':
      '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
  'tokens.txt':
      'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
};

final parakeetAndroidModelFiles = [
  for (final name in sherpaParakeetModelFileNames)
    SttModelFile(
      url: '$_parakeetModelBaseUrl/$name',
      relativePath: name,
      expectedBytes: _parakeetModelFileSizes[name]!,
      expectedSha256: _parakeetModelFileHashes[name]!,
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
