import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';

void main() {
  test('purgeStaleRecordings deletes leftover wav files only', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-purge');
    addTearDown(() => directory.deleteSync(recursive: true));
    final staleWav = File('${directory.path}/typemate-old.wav')
      ..writeAsBytesSync([1, 2, 3]);
    final unrelated = File('${directory.path}/notes.txt')
      ..writeAsStringSync('keep');

    await purgeStaleRecordings(directory);

    expect(staleWav.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('purgeStaleRecordings tolerates a missing directory', () async {
    final missing = Directory(
      '${Directory.systemTemp.path}/typemate-does-not-exist',
    );

    await purgeStaleRecordings(missing);

    expect(missing.existsSync(), isFalse);
  });

  test('purgeStaleRecordings leaves kept failure audio alone', () async {
    // The failed/ folder holds the audio a history entry retries from, so
    // the unconditional sweep must not reach into it.
    final directory = Directory.systemTemp.createTempSync('typemate-purge');
    addTearDown(() => directory.deleteSync(recursive: true));
    final failedDirectory = Directory('${directory.path}/failed')..createSync();
    final kept = File('${failedDirectory.path}/typemate-failed.wav')
      ..writeAsBytesSync([1, 2, 3]);

    await purgeStaleRecordings(directory);

    expect(kept.existsSync(), isTrue);
  });

  test('expired failure audio is swept, recent audio is kept', () async {
    // A WAV can outlive its history entry when the entry's own delete
    // fails, and nothing swept this folder afterwards — so it stayed
    // forever, against the promise that a recording dies with its entry.
    final directory = Directory.systemTemp.createTempSync('typemate-failed');
    addTearDown(() => directory.deleteSync(recursive: true));
    final now = DateTime(2026, 8, 7, 12);
    final expired = File('${directory.path}/old.wav')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(now.subtract(const Duration(days: 31)));
    final recent = File('${directory.path}/recent.wav')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(now.subtract(const Duration(days: 2)));
    final unrelated = File('${directory.path}/notes.txt')
      ..writeAsStringSync('keep')
      ..setLastModifiedSync(now.subtract(const Duration(days: 400)));

    await purgeExpiredFailedRecordings(directory, clock: () => now);

    expect(expired.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue, reason: 'still retryable');
    expect(unrelated.existsSync(), isTrue);
  });

  test('purgeExpiredFailedRecordings tolerates a missing directory', () async {
    final missing = Directory(
      '${Directory.systemTemp.path}/typemate-no-failed-dir',
    );

    await purgeExpiredFailedRecordings(missing);

    expect(missing.existsSync(), isFalse);
  });
}
