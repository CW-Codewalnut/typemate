import 'dart:io';

/// Append-only plain-text log for local troubleshooting: a user can open
/// the log folder from Settings and attach this file to a bug report.
///
/// Privacy contract: entries never contain dictated text or audio — only
/// error causes, timings, and runtime diagnostics (e.g. a speech server's
/// stderr when it fails to start).
///
/// Writes are synchronous (async file IO never completes inside the
/// widget-test fake-async zone) and every failure is swallowed: the log
/// observes the dictation flow and must never break it.
class DiagnosticLog {
  DiagnosticLog({
    required File this.file,
    this.maxSizeBytes = 512 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// A log that goes nowhere, for tests and harnesses that inject nothing.
  const DiagnosticLog.disabled() : file = null, maxSizeBytes = 0, _clock = null;

  final File? file;

  /// Once the file grows past this, it is rotated to `<name>.1` (replacing
  /// any previous rotation) so the log never eats the disk.
  final int maxSizeBytes;

  final DateTime Function()? _clock;

  bool get isEnabled => file != null;

  /// The folder Settings opens for the user, or null when disabled.
  String? get directoryPath => file?.parent.path;

  void log(String area, String message) {
    final target = file;
    if (target == null) {
      return;
    }
    try {
      target.parent.createSync(recursive: true);
      _rotateIfOversized(target);
      final stamp = (_clock ?? DateTime.now)().toIso8601String();
      // Continuation lines are indented so multi-line diagnostics (stderr
      // tails) stay visually attached to their entry.
      final body = message
          .trimRight()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .join('\n    ');
      target.writeAsStringSync(
        '$stamp [$area] $body\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never break the flow it observes.
    }
  }

  void _rotateIfOversized(File target) {
    if (!target.existsSync() || target.lengthSync() < maxSizeBytes) {
      return;
    }
    final rotated = File('${target.path}.1');
    if (rotated.existsSync()) {
      rotated.deleteSync();
    }
    target.renameSync(rotated.path);
  }
}

/// Keeps the last [maxLength] characters fed into it — enough of a child
/// process's stderr to diagnose a failure without buffering unbounded
/// output from a chatty server.
class DiagnosticTailBuffer {
  DiagnosticTailBuffer({this.maxLength = 2000});

  final int maxLength;
  String _tail = '';

  void add(String chunk) {
    _tail = _tail + chunk;
    if (_tail.length > maxLength) {
      _tail = _tail.substring(_tail.length - maxLength);
    }
  }

  String get tail => _tail.trim();
  bool get isEmpty => tail.isEmpty;
}
