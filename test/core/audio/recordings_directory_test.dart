import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';

void main() {
  // Regression: recordings once lived at a CWD-relative build/recordings.
  // The autostart Run-key launch inherits C:\Windows\System32 as CWD, so
  // creating that directory failed and every dictation aborted at login.
  test('recordings live under the APPDATA data directory, not the CWD', () {
    final directory = createDefaultRecordingsDirectory(
      environment: {'APPDATA': r'C:\Users\dev\AppData\Roaming'},
    );

    expect(directory.path, r'C:\Users\dev\AppData\Roaming/TypeMate/recordings');
  });

  test('an explicit data directory override wins', () {
    final directory = createDefaultRecordingsDirectory(
      directory: Directory('build/test-data'),
      environment: {'APPDATA': r'C:\Users\dev\AppData\Roaming'},
    );

    expect(directory.path, 'build/test-data/recordings');
  });

  test('falls back to XDG config home on Linux', () {
    final directory = createDefaultRecordingsDirectory(
      environment: {'XDG_CONFIG_HOME': '/home/dev/.config'},
    );

    expect(directory.path, '/home/dev/.config/TypeMate/recordings');
  });

  test('falls back to HOME when XDG config home is unset', () {
    final directory = createDefaultRecordingsDirectory(
      environment: {'HOME': '/home/dev'},
    );

    expect(directory.path, '/home/dev/.config/TypeMate/recordings');
  });
}
