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
}
