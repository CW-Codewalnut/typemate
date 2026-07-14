import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class DictationHistoryEntry {
  const DictationHistoryEntry({
    required this.text,
    required this.createdAt,
    this.duration = Duration.zero,
  });

  final String text;
  final DateTime createdAt;
  final Duration duration;

  Map<String, Object?> toJson() => {
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
  };

  static DictationHistoryEntry? fromJson(Object? value) {
    if (value case {
      'text': final String text,
      'createdAt': final String rawDate,
    }) {
      final trimmedText = text.trim();
      final createdAt = DateTime.tryParse(rawDate);
      if (trimmedText.isEmpty || createdAt == null) {
        return null;
      }

      final durationMs = value['durationMs'];
      return DictationHistoryEntry(
        text: trimmedText,
        createdAt: createdAt,
        duration: durationMs is int
            ? Duration(milliseconds: durationMs)
            : Duration.zero,
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
  });

  final DictationHistoryStore store;
  final int maxEntries;

  List<DictationHistoryEntry> _entries = const [];
  bool _isLoading = false;

  List<DictationHistoryEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  int get totalWords => _entries.fold(0, (total, entry) {
    final words = entry.text
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;
    return total + words;
  });

  Duration get totalDuration =>
      _entries.fold(Duration.zero, (total, entry) => total + entry.duration);

  int get averageWordsPerMinute {
    final minutes =
        totalDuration.inMilliseconds / Duration.millisecondsPerMinute;
    if (minutes <= 0) {
      return 0;
    }
    return (totalWords / minutes).round();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _entries = await store.loadEntries();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addTranscript(
    String text, {
    Duration duration = Duration.zero,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return;
    }

    _entries = [
      DictationHistoryEntry(
        text: trimmedText,
        createdAt: DateTime.now(),
        duration: duration,
      ),
      ..._entries,
    ].take(maxEntries).toList(growable: false);
    notifyListeners();
    await store.saveEntries(_entries);
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    await store.saveEntries(_entries);
  }
}
