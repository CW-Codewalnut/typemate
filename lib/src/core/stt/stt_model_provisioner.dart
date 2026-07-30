import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One file of a speech model that must exist locally before the engine
/// can load. [relativePath] is resolved inside the provisioner's model
/// directory. [expectedBytes] is the exact size at the pinned revision;
/// a download only counts as complete when the bytes on disk match.
class SttModelFile {
  const SttModelFile({
    required this.url,
    required this.relativePath,
    required this.expectedBytes,
  });

  final String url;
  final String relativePath;
  final int expectedBytes;
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
class SttModelProvisioner extends ChangeNotifier {
  SttModelProvisioner({
    required this.modelDirectory,
    required this.files,
    SttModelFileDownloader? downloader,
  }) : _downloader = downloader ?? _httpDownloader;

  final Directory modelDirectory;
  final List<SttModelFile> files;

  final SttModelFileDownloader _downloader;

  /// Exact size of the full download, summed from the per-file sizes.
  int get expectedTotalBytes =>
      files.fold(0, (sum, file) => sum + file.expectedBytes);

  SttModelProvisionPhase _phase = SttModelProvisionPhase.checking;
  double _progress = 0;
  String? _errorMessage;

  SttModelProvisionPhase get phase => _phase;

  /// 0..1 while downloading.
  double get progress => _progress;

  String? get errorMessage => _errorMessage;

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
  Future<void> refresh() async {
    _setPhase(SttModelProvisionPhase.checking);
    final complete = files.every(_isIntact);
    _setPhase(
      complete
          ? SttModelProvisionPhase.ready
          : SttModelProvisionPhase.downloadRequired,
    );
  }

  /// Downloads every missing file. Safe to call again after a failure;
  /// finished files are skipped and a partial file resumes.
  Future<void> download() async {
    if (_phase == SttModelProvisionPhase.downloading ||
        _phase == SttModelProvisionPhase.ready) {
      return;
    }
    _errorMessage = null;
    _setPhase(SttModelProvisionPhase.downloading);
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
        part.renameSync(target.path);
        completedBytes = baseBytes + file.expectedBytes;
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

/// A dead-but-open connection on flaky mobile networks would otherwise
/// leave the download UI stuck mid-progress forever; when no bytes arrive
/// for this long the download fails into the retry/resume flow instead.
const _downloadIdleTimeout = Duration(seconds: 30);

/// Default downloader: dart:io HttpClient streaming to disk with an HTTP
/// Range request when resuming. Hugging Face and GitHub release hosts both
/// honor ranges and redirects.
Future<void> _httpDownloader(
  SttModelFile file,
  File target, {
  required int resumeFromBytes,
  required void Function(int fileBytes) onProgress,
}) async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse(file.url))
        .timeout(_downloadIdleTimeout);
    if (resumeFromBytes > 0) {
      request.headers.add(HttpHeaders.rangeHeader, 'bytes=$resumeFromBytes-');
    }
    final response = await request.close().timeout(_downloadIdleTimeout);
    final resumed =
        resumeFromBytes > 0 && response.statusCode == HttpStatus.partialContent;
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException(
        'HTTP ${response.statusCode} for ${file.url}',
        uri: Uri.parse(file.url),
      );
    }
    final sink = target.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var fileBytes = resumed ? resumeFromBytes : 0;
    try {
      // Stream.timeout throws when the gap BETWEEN chunks exceeds the
      // idle window — a stall detector, not a cap on total duration.
      await for (final chunk in response.timeout(_downloadIdleTimeout)) {
        sink.add(chunk);
        fileBytes += chunk.length;
        onProgress(fileBytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  } finally {
    client.close();
  }
}
