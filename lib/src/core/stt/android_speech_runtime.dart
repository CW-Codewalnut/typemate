import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import '../audio/audio_denoiser.dart';
import '../diagnostics/diagnostic_reporter.dart';
import 'sherpa_parakeet_stt_engine.dart';
import 'speech_model_catalog.dart';
import 'stt_model_provisioner.dart';

/// The model-download foreground-service notification. `{progress}` is the
/// live percent the package fills in — kept here so a test pins it and it
/// cannot be silently dropped. The title carries no "TypeMate" (Android
/// already shows the app name), and there is no `complete` notification
/// (it fires once per file, stacking four "ready" notifications).
const speechModelDownloadNotification = TaskNotification(
  'Downloading speech model',
  '{progress}',
);

/// The Android speech stack: the on-device Parakeet engine, the first-run
/// downloader for its model files (plus the tiny GTCRN noise-suppression
/// model), and the in-process denoiser behind the Settings toggle. All
/// point at the same directory under the app's private data directory.
({
  SherpaParakeetSttEngine engine,
  SttModelProvisioner provisioner,
  AudioDenoiser denoiser,
})
createAndroidSpeechRuntime({
  required Directory dataDirectory,
  DiagnosticReporter? diagnostics,
}) {
  final modelDirectory = Directory(
    '${dataDirectory.path}/models/$parakeetModelDirectoryName',
  );
  return (
    engine: SherpaParakeetSttEngine(
      modelDirectoryPath: modelDirectory.path,
      diagnostics: diagnostics,
    ),
    provisioner: SttModelProvisioner(
      modelDirectory: modelDirectory,
      files: [...parakeetModelFiles, gtcrnModelFile],
    ),
    denoiser: SherpaGtcrnAudioDenoiser(
      modelPath: '${modelDirectory.path}/${gtcrnModelFile.relativePath}',
    ),
  );
}
