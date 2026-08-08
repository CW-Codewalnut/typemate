import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/text_metrics.dart';

class DictationHistoryEntry {
  const DictationHistoryEntry({
    required this.text,
    required this.createdAt,
    this.duration = Duration.zero,
    this.failureReason,
    this.recordingPath,
  });

  final String text;
  final DateTime createdAt;
  final Duration duration;

  /// Why transcription failed, for entries that hold a recording instead
  /// of text. Null for successful dictations.
  final String? failureReason;

  /// The kept WAV a failed dictation can be retried from. Failed audio is
  /// the one case where a recording outlives its dictation; it is deleted
  /// the moment the entry resolves, is evicted, or history is cleared.
  final String? recordingPath;

  bool get isFailed => failureReason != null;

  /// Value equality, so an entry captured before a `load()` rebuilt the
  /// list still matches its reloaded twin. Identity matching made a
  /// delete or retry from a stale widget silently do nothing, and
  /// createdAt alone is not a key: two dictations can land in the same
  /// millisecond.
  @override
  bool operator ==(Object other) =>
      other is DictationHistoryEntry &&
      other.text == text &&
      other.createdAt == createdAt &&
      other.duration == duration &&
      other.failureReason == failureReason &&
      other.recordingPath == recordingPath;

  @override
  int get hashCode =>
      Object.hash(text, createdAt, duration, failureReason, recordingPath);

  Map<String, Object?> toJson() => {
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    if (failureReason != null) 'failureReason': failureReason,
    if (recordingPath != null) 'recordingPath': recordingPath,
  };

  static DictationHistoryEntry? fromJson(Object? value) {
    if (value case {
      'text': final String text,
      'createdAt': final String rawDate,
    }) {
      final trimmedText = text.trim();
      final createdAt = DateTime.tryParse(rawDate);
      final failureReason = switch (value['failureReason']) {
        final String reason when reason.trim().isNotEmpty => reason.trim(),
        _ => null,
      };
      if (createdAt == null) {
        return null;
      }
      if (failureReason == null &&
          (trimmedText.isEmpty || isSilentAudioTranscript(trimmedText))) {
        return null;
      }

      final durationMs = value['durationMs'];
      final recordingPath = value['recordingPath'];
      return DictationHistoryEntry(
        text: trimmedText,
        createdAt: createdAt,
        duration: durationMs is int
            ? Duration(milliseconds: durationMs)
            : Duration.zero,
        failureReason: failureReason,
        recordingPath: recordingPath is String && recordingPath.isNotEmpty
            ? recordingPath
            : null,
      );
    }

    return null;
  }
}

abstract interface class DictationHistoryStore {
  Future<List<DictationHistoryEntry>> loadEntries();
  Future<void> saveEntries(List<DictationHistoryEntry> entries);
}

class NoopDictationHistoryStore implements DictationHistoryStore {
  const NoopDictationHistoryStore();

  @override
  Future<List<DictationHistoryEntry>> loadEntries() async => const [];

  @override
  Future<void> saveEntries(List<DictationHistoryEntry> entries) async {}
}

class FileDictationHistoryStore implements DictationHistoryStore {
  const FileDictationHistoryStore({required this.file});

  final File file;

  @override
  Future<List<DictationHistoryEntry>> loadEntries() async {
    if (!await file.exists()) {
      return const [];
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded case {'entries': final List<Object?> values}) {
      return [
        for (final value in values) DictationHistoryEntry.fromJson(value),
      ].whereType<DictationHistoryEntry>().toList(growable: false);
    }

    return const [];
  }

  @override
  Future<void> saveEntries(List<DictationHistoryEntry> entries) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'entries': entries.map((entry) => entry.toJson()).toList()}),
      flush: true,
    );
  }
}

class DictationHistoryController extends ChangeNotifier {
  DictationHistoryController({
    this.store = const NoopDictationHistoryStore(),
    this.maxEntries = 100,
    this.failedEntryMaxAge = const Duration(days: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DictationHistoryStore store;
  final int maxEntries;

  /// A failed dictation the user never retried is not kept forever: past
  /// this age its recording and entry are deleted on load.
  final Duration failedEntryMaxAge;

  final DateTime Function() _clock;

  List<DictationHistoryEntry> _entries = const [];
  bool _isLoading = false;

  List<DictationHistoryEntry> get entries => _entries;

  /// Failed entries hold recordings, not words; stats count only real
  /// transcripts.
  List<DictationHistoryEntry> get successfulEntries =>
      _entries.where((entry) => !entry.isFailed).toList(growable: false);

  bool get isLoading => _isLoading;
  int get totalWords => successfulEntries.fold(
    0,
    (total, entry) => total + wordCount(entry.text),
  );

  Duration get totalDuration => successfulEntries.fold(
    Duration.zero,
    (total, entry) => total + entry.duration,
  );

  int get averageWordsPerMinute =>
      calculateAverageWordsPerMinute(totalWords, totalDuration);

  /// Coalesces overlapping calls: app bootstrap and the home screen each
  /// ask for a load on launch, which read the file twice and produced two
  /// notify storms. A caller already waiting gets the in-flight read.
  Future<void>? _loading;

  Future<void> load() {
    final inFlight = _loading;
    if (inFlight != null) {
      return inFlight;
    }
    final attempt = _load();
    _loading = attempt;
    return attempt.whenComplete(() {
      if (identical(_loading, attempt)) {
        _loading = null;
      }
    });
  }

  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();
    final loaded = await store.loadEntries();
    // Expire failed dictations the user never retried: past the age limit
    // both the entry and its kept recording go away.
    final cutoff = _clock().subtract(failedEntryMaxAge);
    final kept = <DictationHistoryEntry>[];
    var expiredAny = false;
    for (final entry in loaded) {
      if (entry.isFailed && entry.createdAt.isBefore(cutoff)) {
        _deleteRecordingQuietly(entry);
        expiredAny = true;
      } else {
        kept.add(entry);
      }
    }
    _entries = kept.toList(growable: false);
    _isLoading = false;
    notifyListeners();
    if (expiredAny) {
      await store.saveEntries(_entries);
    }
  }

  Future<void> addTranscript(
    String text, {
    Duration duration = Duration.zero,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty || isSilentAudioTranscript(trimmedText)) {
      return;
    }

    await _prepend(
      DictationHistoryEntry(
        text: trimmedText,
        createdAt: _clock(),
        duration: duration,
      ),
    );
  }

  /// Records a failed dictation, optionally holding on to its recording so
  /// the user can retry the transcription later.
  Future<void> addFailure(
    String reason, {
    String? recordingPath,
    Duration duration = Duration.zero,
  }) async {
    await _prepend(
      DictationHistoryEntry(
        text: '',
        createdAt: _clock(),
        duration: duration,
        failureReason: reason,
        recordingPath: recordingPath,
      ),
    );
  }

  /// A successful retry: the failed entry becomes a normal transcript in
  /// place (keeping its original time) and its recording is deleted.
  Future<void> resolveFailedEntry(
    DictationHistoryEntry entry,
    String transcript,
  ) async {
    final trimmed = transcript.trim();
    _deleteRecordingQuietly(entry);
    _entries = [
      for (final existing in _entries)
        if (existing != entry)
          existing
        // Silence on retry means there is nothing worth keeping.
        else if (trimmed.isNotEmpty && !isSilentAudioTranscript(trimmed))
          DictationHistoryEntry(
            text: trimmed,
            createdAt: entry.createdAt,
            duration: entry.duration,
          ),
    ];
    notifyListeners();
    await store.saveEntries(_entries);
  }

  /// When [entry] and its kept recording are deleted by the 30-day sweep,
  /// shown on the entry so the user knows the recording does not sit
  /// around forever.
  DateTime failedEntryExpiry(DictationHistoryEntry entry) =>
      entry.createdAt.add(failedEntryMaxAge);

  /// Immediate deletion by the user: the entry goes away now and takes its
  /// kept recording with it.
  Future<void> removeEntry(DictationHistoryEntry entry) async {
    _deleteRecordingQuietly(entry);
    _entries = [
      for (final existing in _entries)
        if (existing != entry) existing,
    ];
    notifyListeners();
    await store.saveEntries(_entries);
  }

  /// A retry that failed again: the entry keeps its recording but shows
  /// the fresh reason.
  Future<void> updateFailureReason(
    DictationHistoryEntry entry,
    String reason,
  ) async {
    _entries = [
      for (final existing in _entries)
        if (existing == entry)
          DictationHistoryEntry(
            text: '',
            createdAt: entry.createdAt,
            duration: entry.duration,
            failureReason: reason,
            recordingPath: entry.recordingPath,
          )
        else
          existing,
    ];
    notifyListeners();
    await store.saveEntries(_entries);
  }

  Future<void> clear() async {
    for (final entry in _entries) {
      _deleteRecordingQuietly(entry);
    }
    _entries = const [];
    notifyListeners();
    await store.saveEntries(_entries);
  }

  Future<void> _prepend(DictationHistoryEntry entry) async {
    final capped = [entry, ..._entries];
    // Evicted failed entries take their kept recordings with them.
    for (final evicted in capped.skip(maxEntries)) {
      _deleteRecordingQuietly(evicted);
    }
    _entries = capped.take(maxEntries).toList(growable: false);
    notifyListeners();
    await store.saveEntries(_entries);
  }

  void _deleteRecordingQuietly(DictationHistoryEntry entry) {
    final path = entry.recordingPath;
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      // Synchronous on purpose: async file IO never completes inside the
      // widget-test fake-async zone.
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best effort; an undeletable file is retried on the next sweep.
    }
  }
}
