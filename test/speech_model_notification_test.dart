import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/stt/android_speech_runtime.dart';

void main() {
  test('download notification shows the live percentage', () {
    // Regression guard: the {progress} placeholder is what puts the
    // percent in the notification. Do not remove it.
    expect(speechModelDownloadNotification.body, contains('{progress}'));
  });

  test('download notification title does not duplicate the app name', () {
    // Android already shows "TypeMate" as the notification source; a
    // "TypeMate" title on top of that shows it twice.
    expect(
      speechModelDownloadNotification.title.toLowerCase(),
      isNot(contains('typemate')),
    );
  });
}
