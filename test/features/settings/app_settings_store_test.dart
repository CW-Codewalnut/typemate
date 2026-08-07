import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/microphone_settings_store.dart';

void main() {
  test('creates file-backed microphone settings store under APPDATA', () async {
    final store = createDefaultMicrophoneSettingsStore(
      environment: {'APPDATA': 'build/test-appdata'},
    );

    expect(store, isA<FileMicrophoneSettingsStore>());
    await store.saveSelectedMicrophoneName('USB Mic');

    final file = File('build/test-appdata/TypeMate/settings.json');
    expect(await file.exists(), isTrue);
    expect(await store.loadSelectedMicrophoneName(), 'USB Mic');
  });
}
