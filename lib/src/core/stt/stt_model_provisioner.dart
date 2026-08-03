import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// One file of a speech model that must exist locally before the engine
/// can load. [relativePath] is resolved inside the provisioner's model
/// directory. [expectedBytes] is the exact size at the pinned revision,
/// and [expectedSha256] the exact content hash; a download only counts
/// as complete when both match — a corrupt model file crashes the native
/// loader (an uncatchable process abort), so nothing unverified may ever
/// reach it.
class SttModelFile {
  const SttModelFile({
    required this.url,
    required this.relativePath,
    required this.expectedBytes,
    this.expectedSha256,
  });

  final String url;
  final String relativePath;
  final int expectedBytes;

  /// Lowercase hex SHA-256 of the file at the pinned revision; null
  /// skips the hash gate (tests).
  final String? expectedSha256;
}

/// Streams [file] to [target]. [resumeFromBytes] > 0 asks the server for
/// the remainder (HTTP Range) and appends. [onProgress] reports the total
/// bytes present in the file so far — including resumed bytes, and
/// restarting from zero when the server ignored the range request.
typedef SttModelFileDownloader =
    Future<void> Function(
      SttModelFile file,
      File target, {
      required int resumeFromBytes,
      required void Function(int fileBytes) onProgress,
    });

enum SttModelProvisionPhase {
  /// Local files are being checked.
  checking,

  /// One or more files are missing; a download is needed.
  downloadRequired,

  downloading,

  /// Every file is present; the engine can load.
  ready,

  failed,
}

/// The surface the download UI binds to. [SttModelProvisioner] is the one
/// real implementation for a single model; the desktop wraps several of
/// them behind this same surface so the UI shows whichever model the
/// selected language needs.
abstract class SpeechModelProvisioner extends ChangeNotifier {
  SttModelProvisionPhase get phase;

  /// 0..1 while downloading.
  double get progress;

  String? get errorMessage;

  bool get isReady;

  /// Exact size of the full download in bytes.
  int get expectedTotalBytes;

  Future<void> refresh();

  Future<void> download();
}

/// Owns the first-run download of the on-device speech model (Android).
/// The model is too large to bundle in the app package, so it streams into
/// the app's private data directory once; every later launch finds it
/// [SttModelProvisionPhase.ready] immediately.
///
/// Each file downloads to a `.part` sibling and only renames to its final
/// name after its size matches the pinned revision's exact byte count, so
/// a killed app, a truncated stream, or a server serving different bytes
/// can never leave a corrupt file that looks complete. An existing
/// `.part` resumes where it stopped.
class SttModelProvisioner extends SpeechModelProvisioner {
  SttModelProvisioner({
    required this.modelDirectory,
    required this.files,
    SttModelFileDownloader? downloader,
    Future<void> Function()? ensureNotificationPermission,
    Future<bool> Function()? hasActiveDownload,
  }) : _downloader = downloader ?? _packageDownloader,
       // The real package integrations (notification permission, download
       // manager query) only apply when using the real downloader; an
       // injected downloader (tests) skips them unless it opts in.
       _ensureNotificationPermission =
           ensureNotificationPermission ??
           (downloader == null ? _requestNotificationPermission : null),
       _hasActiveDownload =
           hasActiveDownload ??
           (downloader == null ? null : (() async => false));

  final Directory modelDirectory;
  final List<SttModelFile> files;

  final SttModelFileDownloader _downloader;

  /// Asks for the foreground-service notification permission before a
  /// download; null (tests) skips it.
  final Future<void> Function()? _ensureNotificationPermission;

  /// Whether a download is already running on the OS download manager
  /// (a foreground-service download survives the app being killed); null
  /// defaults to querying the real download manager.
  final Future<bool> Function()? _hasActiveDownload;

  /// Exact size of the full download, summed from the per-file sizes.
  @override
  int get expectedTotalBytes =>
      files.fold(0, (sum, file) => sum + file.expectedBytes);

  SttModelProvisionPhase _phase = SttModelProvisionPhase.checking;
  double _progress = 0;
  String? _errorMessage;

  @override
  SttModelProvisionPhase get phase => _phase;

  /// 0..1 while downloading.
  @override
  double get progress => _progress;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get isReady => _phase == SttModelProvisionPhase.ready;

  File _targetFor(SttModelFile file) =>
      File('${modelDirectory.path}/${file.relativePath}');

  File _partFor(SttModelFile file) =>
      File('${modelDirectory.path}/${file.relativePath}.part');

  /// A completed file must also still have the pinned revision's exact
  /// size: the validated rename guarantees it was right once, but this
  /// additionally catches outside interference with app storage.
  bool _isIntact(SttModelFile file) {
    final target = _targetFor(file);
    return target.existsSync() && target.lengthSync() == file.expectedBytes;
  }

  /// Checks which files already exist (at their exact pinned size) and
  /// lands in [SttModelProvisionPhase.ready] or
  /// [SttModelProvisionPhase.downloadRequired].
  ///
  /// A refresh must never hide an active download: the provisioner is a
  /// long-lived singleton, and every return to the dictation surface
  /// re-checks it while a download may be running.
  @override
  Future<void> refresh() async {
    if (_phase == SttModelProvisionPhase.downloading) {
      return;
    }
    _setPhase(SttModelProvisionPhase.checking);
    if (files.every(_isIntact)) {
      _setPhase(SttModelProvisionPhase.ready);
      return;
    }
    // A download from a previous launch may still be running on the OS
    // download manager (a foreground-service download outlives the app).
    // Adopt it — show live "downloading" and drive it to completion —
    // instead of offering a Download button the user could double-tap
    // into a second, racing download.
    if (await (_hasActiveDownload?.call() ?? _queryDownloadManager())) {
      await download();
      return;
    }
    _setPhase(SttModelProvisionPhase.downloadRequired);
  }

  /// Asks the real download manager whether any of this model's files is
  /// still being downloaded (from a previous, possibly killed, launch).
  ///
  /// Android only: WorkManager keeps a foreground-service download running
  /// after the app process dies, so a live record there is a real
  /// download to adopt. On desktop the download dies with the app, so a
  /// "running" record found at startup is stale by definition — adopting
  /// it would poll a record nothing will ever update again, showing a
  /// download bar frozen at its last progress forever.
  Future<bool> _queryDownloadManager() async {
    if (!Platform.isAndroid) {
      return false;
    }
    for (final file in files) {
      final taskId = 'typemate-model-${_partFor(file).uri.pathSegments.last}';
      final record = await FileDownloader().database.recordForId(taskId);
      if (record != null &&
          (record.status == TaskStatus.running ||
              record.status == TaskStatus.enqueued ||
              record.status == TaskStatus.waitingToRetry ||
              record.status == TaskStatus.paused)) {
        return true;
      }
    }
    return false;
  }

  /// Downloads every missing file. Safe to call again after a failure;
  /// finished files are skipped and a partial file resumes.
  @override
  Future<void> download() async {
    if (_phase == SttModelProvisionPhase.downloading ||
        _phase == SttModelProvisionPhase.ready) {
      return;
    }
    _errorMessage = null;
    _setPhase(SttModelProvisionPhase.downloading);
    // The download runs on a foreground service whose notification needs
    // the Android 13+ runtime permission; without it the OS suppresses
    // the notification AND kills the job the moment the app is minimized.
    // Best-effort: the download still tries if the user declines.
    await _ensureNotificationPermission?.call();
    // Synchronous on purpose: async file IO never completes inside the
    // widget-test fake-async zone.
    modelDirectory.createSync(recursive: true);

    var completedBytes = 0;
    for (final file in files) {
      final target = _targetFor(file);
      // Same intactness bar as refresh(): a completed file that lost its
      // exact size is re-downloaded, not skipped by existence alone.
      if (_isIntact(file)) {
        completedBytes += file.expectedBytes;
        _reportProgress(completedBytes);
        continue;
      }
      if (target.existsSync()) {
        target.deleteSync();
      }
      final part = _partFor(file);
      final resumeFromBytes = part.existsSync() ? part.lengthSync() : 0;
      final baseBytes = completedBytes;
      _reportProgress(baseBytes + resumeFromBytes);
      try {
        await _downloader(
          file,
          part,
          resumeFromBytes: resumeFromBytes,
          onProgress: (fileBytes) => _reportProgress(baseBytes + fileBytes),
        );
        final actualBytes = part.existsSync() ? part.lengthSync() : 0;
        if (actualBytes != file.expectedBytes) {
          // Wrong size means the stream ended early or the server sent
          // different bytes; keep nothing so the retry starts clean
          // instead of resuming a file that can never validate.
          if (part.existsSync()) {
            part.deleteSync();
          }
          throw StateError(
            '${file.relativePath} downloaded $actualBytes bytes, '
            'expected ${file.expectedBytes}',
          );
        }
        final expectedHash = file.expectedSha256;
        if (expectedHash != null) {
          // Hash the (up to 622 MB) file in a background isolate so it
          // does not jank the UI at download completion.
          final digest = await compute(_sha256OfFile, part.path);
          if (digest != expectedHash) {
            part.deleteSync();
            throw StateError(
              '${file.relativePath} failed its checksum: the content does '
              'not match the pinned revision',
            );
          }
        }
        part.renameSync(target.path);
        completedBytes = baseBytes + file.expectedBytes;
      } on SttDownloadCanceled {
        // The user tapped Cancel on the download notification. That is a
        // deliberate stop, not a failure: drop any partials and return to
        // the Download button so a later tap starts fresh.
        _progress = 0;
        for (final f in files) {
          final p = _partFor(f);
          if (p.existsSync()) {
            p.deleteSync();
          }
        }
        _setPhase(SttModelProvisionPhase.downloadRequired);
        return;
      } catch (error) {
        _errorMessage =
            'Download interrupted. Check your connection and try again.';
        debugPrint('TypeMate: model download failed for ${file.url}: $error');
        _setPhase(SttModelProvisionPhase.failed);
        return;
      }
    }
    _progress = 1;
    _setPhase(SttModelProvisionPhase.ready);
  }

  void _reportProgress(int bytes) {
    final total = expectedTotalBytes;
    final fraction = total <= 0 ? 0.0 : (bytes / total).clamp(0.0, 1.0);
    if ((fraction - _progress).abs() < 0.001) {
      return;
    }
    _progress = fraction;
    notifyListeners();
  }

  void _setPhase(SttModelProvisionPhase phase) {
    _phase = phase;
    notifyListeners();
  }
}

/// Requests the notification permission through the same package that
/// owns the download, so no extra permission plugin is pulled in. A
/// granted (or not-applicable) result needs no action; a denial just
/// means the download runs without its foreground notification.
///
/// Android-only: desktop downloads run in-process with no
/// foreground-service notification, and the package's permission
/// channel is not implemented on macOS.
Future<void> _requestNotificationPermission() async {
  if (!Platform.isAndroid) {
    return;
  }
  final status = await FileDownloader().permissions.status(
    PermissionType.notifications,
  );
  if (status != PermissionStatus.granted) {
    await FileDownloader().permissions.request(PermissionType.notifications);
  }
}

/// Default downloader: the background_downloader package, one Dart API
/// over every platform's native download machinery (retries, pause and
/// resume, keeps going while the app is backgrounded, progress
/// notification when configured). Downloads land in the package's temp
/// area and are moved into the caller's target so the size and checksum
/// gates above always run before a file can look complete.
Future<void> _packageDownloader(
  SttModelFile file,
  File target, {
  required int resumeFromBytes,
  required void Function(int fileBytes) onProgress,
}) async {
  // resumeFromBytes is unused: the package keeps its own resume data.
  final task = DownloadTask(
    // Deterministic id: one task identity per model file, so a file
    // WorkManager finished after the app process died is found again.
    taskId: 'typemate-model-${target.uri.pathSegments.last}',
    url: file.url,
    baseDirectory: BaseDirectory.temporary,
    directory: 'typemate_model_download',
    filename: target.uri.pathSegments.last,
    updates: Updates.statusAndProgress,
    retries: 5,
    allowPause: true,
  );

  // Android: the foreground-service download keeps going even after the
  // app is killed. On reopen the same file may already be finished, or
  // still running — adopt either instead of starting a second copy that
  // races the first (the "two downloads, progress bouncing" bug). Only
  // adopt a genuinely live or complete task; a canceled/failed record is
  // stale and must be cleared, or a fresh Download would re-adopt it and
  // immediately re-cancel ("tapping Download does nothing").
  //
  // Desktop: the download dies with the app, so only a COMPLETE record
  // (killed between finish and rename) is adoptable; a "running" record
  // from a previous launch is stale and is cleared like any other —
  // adopting it would poll forever against a dead download.
  final previous = await FileDownloader().database.recordForId(task.taskId);
  final adoptable = <TaskStatus>{
    TaskStatus.complete,
    if (Platform.isAndroid) ...{
      TaskStatus.running,
      TaskStatus.enqueued,
      TaskStatus.waitingToRetry,
      TaskStatus.paused,
    },
  };
  if (previous != null && adoptable.contains(previous.status)) {
    if (await _adoptRunningDownload(task, file, onProgress)) {
      _moveIntoPlace(File(await task.filePath()), target);
      return;
    }
  } else if (previous != null) {
    // Stale record (canceled/failed anywhere; also killed-mid-run on
    // desktop). Cancel the underlying job AND drop the record, so the
    // fresh enqueue below is not shadowed by a still-clearing job —
    // otherwise the first Download tap silently no-ops and only the
    // second works.
    await FileDownloader().cancelTaskWithId(task.taskId);
    await FileDownloader().database.deleteRecordWithId(task.taskId);
  }

  // The foreground service keeps the download alive across backgrounding
  // and app kills, so a cancellation now means one thing: the user tapped
  // Cancel on the notification. That is terminal, not a retry.
  final result = await FileDownloader().download(
    task,
    onProgress: (fraction) {
      if (fraction > 0) {
        onProgress((fraction * file.expectedBytes).round());
      }
    },
  );
  if (result.status == TaskStatus.complete) {
    _moveIntoPlace(File(await task.filePath()), target);
    return;
  }
  if (result.status == TaskStatus.canceled) {
    throw const SttDownloadCanceled();
  }
  throw StateError(
    'download of ${file.relativePath} ended as ${result.status}'
    '${result.exception == null ? '' : ': ${result.exception}'}',
  );
}

/// Lowercase hex SHA-256 of a file, computed in a background isolate via
/// `compute` so hashing a large model file never janks the UI.
Future<String> _sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// A [SttModelFileDownloader] throws this when the user cancels the
/// download (e.g. from its notification), so the provisioner returns to
/// the Download button rather than treating the deliberate stop as a
/// failure.
class SttDownloadCanceled implements Exception {
  const SttDownloadCanceled();
}

/// Waits on a download that a previous app launch started and left
/// running on the foreground service. Returns true if it reached the
/// cache file (caller moves it into place), false if it is not actually
/// in flight (or ended without a file), so the caller downloads fresh.
///
/// Polls the persisted task record rather than the updates stream: after
/// an app restart the stream can miss events that already fired, but the
/// record is durable and race-free.
Future<bool> _adoptRunningDownload(
  DownloadTask task,
  SttModelFile file,
  void Function(int fileBytes) onProgress,
) async {
  final cacheFile = File(await task.filePath());
  while (true) {
    final record = await FileDownloader().database.recordForId(task.taskId);
    if (record == null) {
      return false;
    }
    if (record.progress > 0) {
      onProgress((record.progress * file.expectedBytes).round());
    }
    if (record.status == TaskStatus.complete) {
      return cacheFile.existsSync();
    }
    if (record.status == TaskStatus.canceled) {
      // The user canceled the adopted download from its notification.
      throw const SttDownloadCanceled();
    }
    if (record.status == TaskStatus.enqueued ||
        record.status == TaskStatus.running ||
        record.status == TaskStatus.waitingToRetry ||
        record.status == TaskStatus.paused) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      continue;
    }
    // failed / notFound: not adoptable, download fresh.
    return false;
  }
}

void _moveIntoPlace(File downloaded, File target) {
  try {
    downloaded.renameSync(target.path);
  } on FileSystemException {
    // Temp and data can live on different volumes; copy instead.
    downloaded.copySync(target.path);
    downloaded.deleteSync();
  }
}
