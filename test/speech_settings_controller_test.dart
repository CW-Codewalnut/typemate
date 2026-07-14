import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';

void main() {
  group('speechLanguageOptions', () {
    test('exposes Whisper supported language list for the language input', () {
      expect(speechLanguageOptions.length, greaterThanOrEqualTo(100));
      expect(speechLanguageOptions.first.code, 'auto');
      expect(speechLanguageOptions.first.label, 'Auto');
      expect(
        speechLanguageOptions.map((language) => language.code),
        containsAll(['en', 'hi', 'ta', 'bn', 'ur', 'zh', 'yue', 'sw']),
      );
    });

    test('has unique language codes and labels', () {
      final codes = speechLanguageOptions.map((language) => language.code);
      final labels = speechLanguageOptions.map((language) => language.label);

      expect(codes.toSet(), hasLength(speechLanguageOptions.length));
      expect(labels.toSet(), hasLength(speechLanguageOptions.length));
    });
  });
}
