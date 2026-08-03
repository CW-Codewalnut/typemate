import 'package:background_downloader/background_downloader.dart';

/// The model-download foreground-service notification. `{progress}` is the
/// live percent the package fills in — kept here so a test pins it and it
/// cannot be silently dropped. The title carries no "TypeMate" (Android
/// already shows the app name), and there is no `complete` notification
/// (it fires once per file, stacking a "ready" notification per file).
///
/// The speech stack itself is the same on every platform now — see
/// `createSpeechRuntime` — so this file only keeps the
/// Android-specific download-notification wording.
const speechModelDownloadNotification = TaskNotification(
  'Downloading speech model',
  '{progress}',
);
