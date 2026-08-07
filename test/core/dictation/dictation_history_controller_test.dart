import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/dictation_history_controller.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('typemate-history');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  File wavFile(String name) =>
      File('${temp.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('failed entries round-trip through the store', () async {
    final store = _MemoryStore();
    final controller = DictationHistoryController(store: store);

    await controller.addFailure(
      'Couldn\'t turn your speech into text.',
      recordingPath: 'recordings/failed/clip.wav',
      duration: const Duration(seconds: 3),
    );

    final reloaded = DictationHistoryController(store: store);
    await reloaded.load();

    final entry = reloaded.entries.single;
    expect(entry.isFailed, isTrue);
    expect(entry.failureReason, 'Couldn\'t turn your speech into text.');
    expect(entry.recordingPath, 'recordings/failed/clip.wav');
    expect(entry.duration, const Duration(seconds: 3));
    expect(entry.text, isEmpty);
  });

  test('legacy entries without failure fields still load', () async {
    // The raw JSON shape an old build wrote: no failure fields at all.
    final store = _MemoryStore()
      ..rawOverride = {
        'entries': [
          {'text': 'old transcript', 'createdAt': '2026-06-01T10:00:00.000'},
        ],
      };
    final controller = DictationHistoryController(store: store);

    await controller.load();

    expect(controller.entries.single.text, 'old transcript');
    expect(controller.entries.single.isFailed, isFalse);
  });

  test('resolving a failed entry replaces it and deletes the WAV', () async {
    final wav = wavFile('kept.wav');
    final controller = DictationHistoryController(store: _MemoryStore());
    await controller.addFailure('failed', recordingPath: wav.path);
    final failedEntry = controller.entries.single;

    await controller.resolveFailedEntry(failedEntry, ' Recovered text. ');

    final entry = controller.entries.single;
    expect(entry.isFailed, isFalse);
    expect(entry.text, 'Recovered text.');
    expect(entry.createdAt, failedEntry.createdAt);
    expect(wav.existsSync(), isFalse);
  });

  test('a silent retry removes the entry entirely', () async {
    final wav = wavFile('kept.wav');
    final controller = DictationHistoryController(store: _MemoryStore());
    await controller.addFailure('failed', recordingPath: wav.path);

    await controller.resolveFailedEntry(controller.entries.single, '   ');

    expect(controller.entries, isEmpty);
    expect(wav.existsSync(), isFalse);
  });

  test('a repeat failure updates the reason and keeps the WAV', () async {
    final wav = wavFile('kept.wav');
    final controller = DictationHistoryController(store: _MemoryStore());
    await controller.addFailure('first reason', recordingPath: wav.path);

    await controller.updateFailureReason(
      controller.entries.single,
      'second reason',
    );

    final entry = controller.entries.single;
    expect(entry.failureReason, 'second reason');
    expect(entry.recordingPath, wav.path);
    expect(wav.existsSync(), isTrue);
  });

  test('removeEntry deletes the entry and its kept recording now', () async {
    final wav = wavFile('kept.wav');
    final controller = DictationHistoryController(store: _MemoryStore());
    await controller.addTranscript('keep me');
    await controller.addFailure('failed', recordingPath: wav.path);

    await controller.removeEntry(
      controller.entries.singleWhere((entry) => entry.isFailed),
    );

    expect(controller.entries.single.text, 'keep me');
    expect(wav.existsSync(), isFalse);
  });

  test('failedEntryExpiry is the entry age limit from creation', () async {
    final controller = DictationHistoryController(
      store: _MemoryStore(),
      clock: () => DateTime(2026, 7, 27, 12),
    );
    await controller.addFailure('failed');

    expect(
      controller.failedEntryExpiry(controller.entries.single),
      DateTime(2026, 8, 26, 12),
    );
  });

  test('clearing history deletes kept recordings', () async {
    final wav = wavFile('kept.wav');
    final controller = DictationHistoryController(store: _MemoryStore());
    await controller.addFailure('failed', recordingPath: wav.path);

    await controller.clear();

    expect(controller.entries, isEmpty);
    expect(wav.existsSync(), isFalse);
  });

  test('evicted failed entries take their recordings with them', () async {
    final wav = wavFile('kept.wav');
    final controller = DictationHistoryController(
      store: _MemoryStore(),
      maxEntries: 2,
    );
    await controller.addFailure('failed', recordingPath: wav.path);
    await controller.addTranscript('one');
    await controller.addTranscript('two');

    expect(controller.entries, hasLength(2));
    expect(controller.entries.any((entry) => entry.isFailed), isFalse);
    expect(wav.existsSync(), isFalse);
  });

  test('failed entries expire after the max age on load', () async {
    final oldWav = wavFile('old.wav');
    final freshWav = wavFile('fresh.wav');
    final store = _MemoryStore();
    var now = DateTime(2026, 6, 1);
    final writer = DictationHistoryController(store: store, clock: () => now);
    await writer.addFailure('too old', recordingPath: oldWav.path);
    now = DateTime(2026, 7, 20);
    await writer.addFailure('still fresh', recordingPath: freshWav.path);

    final reader = DictationHistoryController(
      store: store,
      clock: () => DateTime(2026, 7, 27),
    );
    await reader.load();

    expect(reader.entries.single.failureReason, 'still fresh');
    expect(oldWav.existsSync(), isFalse);
    expect(freshWav.existsSync(), isTrue);
    // The pruned list was persisted so the expiry does not repeat.
    expect(store.saved, hasLength(1));
  });

  test('stats count only successful dictations', () async {
    final controller = DictationHistoryController(store: _MemoryStore());
    await controller.addTranscript(
      'three words here',
      duration: const Duration(seconds: 30),
    );
    await controller.addFailure(
      'failed',
      duration: const Duration(seconds: 30),
    );

    expect(controller.totalWords, 3);
    expect(controller.totalDuration, const Duration(seconds: 30));
    expect(controller.successfulEntries, hasLength(1));
    expect(controller.entries, hasLength(2));
  });
}

class _MemoryStore implements DictationHistoryStore {
  List<DictationHistoryEntry> saved = const [];
  Map<String, Object?>? rawOverride;

  @override
  Future<List<DictationHistoryEntry>> loadEntries() async {
    final raw = rawOverride;
    if (raw != null) {
      return [
        for (final value in raw['entries'] as List<Object?>)
          DictationHistoryEntry.fromJson(value),
      ].whereType<DictationHistoryEntry>().toList(growable: false);
    }
    // Round-trip through JSON so serialization is part of the test.
    return [
      for (final entry in saved) DictationHistoryEntry.fromJson(entry.toJson()),
    ].whereType<DictationHistoryEntry>().toList(growable: false);
  }

  @override
  Future<void> saveEntries(List<DictationHistoryEntry> entries) async {
    saved = List.of(entries);
  }
}
