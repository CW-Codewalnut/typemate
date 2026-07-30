import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One file of a speech model that must exist locally before the engine
/// can load. [relativePath] is resolved inside the provisioner's model
/// directory.
class SttModelFile {
  const SttModelFile({required this.url, required this.relativePath});

  final String url;
  final String relativePath;
}

/// Streams [file] to [target], reporting received byte counts through
/// [onProgress]. [resumeFromBytes] > 0 asks the server for the remainder
/// (HTTP Range) and appends.
typedef SttModelFileDownloader =
    Future<void> Function(
      SttModelFile file,
      File target, {
      required int resumeFromBytes,
      required void Function(int receivedBytes) onProgress,
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
/// name after completing, so a killed app never leaves a truncated file
/// that looks complete. An existing `.part` resumes where it stopped.
class SttModelProvisioner extends ChangeNotifier {
  SttModelProvisioner({
    required this.modelDirectory,
    required this.files,
    required this.expectedTotalBytes,
    SttModelFileDownloader? downloader,
  }) : _downloader = downloader ?? _httpDownloader;

  final Directory modelDirectory;
  final List<SttModelFile> files;

  /// Approximate size of the full download, for the progress fraction and
  /// the user-facing size label. Completion is decided per file by its
  /// rename, never by this number.
  final int expectedTotalBytes;

  final SttModelFileDownloader _downloader;

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

  /// Checks which files already exist and lands in
  /// [SttModelProvisionPhase.ready] or
  /// [SttModelProvisionPhase.downloadRequired].
  Future<void> refresh() async {
    _setPhase(SttModelProvisionPhase.checking);
    final complete = files.every((file) => _targetFor(file).existsSync());
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
      if (target.existsSync()) {
        completedBytes += target.lengthSync();
        _reportProgress(completedBytes);
        continue;
      }
      final part = _partFor(file);
      final resumeFromBytes = part.existsSync() ? part.lengthSync() : 0;
      completedBytes += resumeFromBytes;
      _reportProgress(completedBytes);
      final baseBytes = completedBytes;
      try {
        await _downloader(
          file,
          part,
          resumeFromBytes: resumeFromBytes,
          onProgress: (receivedBytes) =>
              _reportProgress(baseBytes + receivedBytes),
        );
        part.renameSync(target.path);
        completedBytes = baseBytes + (target.lengthSync() - resumeFromBytes);
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
    final fraction = expectedTotalBytes <= 0
        ? 0.0
        : (bytes / expectedTotalBytes).clamp(0.0, 1.0);
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

/// Default downloader: dart:io HttpClient streaming to disk with an HTTP
/// Range request when resuming. Hugging Face and GitHub release hosts both
/// honor ranges and redirects.
Future<void> _httpDownloader(
  SttModelFile file,
  File target, {
  required int resumeFromBytes,
  required void Function(int receivedBytes) onProgress,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(file.url));
    if (resumeFromBytes > 0) {
      request.headers.add(HttpHeaders.rangeHeader, 'bytes=$resumeFromBytes-');
    }
    final response = await request.close();
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
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  } finally {
    client.close();
  }
}
