import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';

void main() {
  group('speechLanguageOptions', () {
    test('only lists languages the bundled model transcribes well', () {
      expect(speechLanguageOptions.first.code, 'auto');
      expect(speechLanguageOptions.first.label, 'Auto');

      // Core languages that must stay available.
      expect(
        speechLanguageOptions.map((language) => language.code),
        containsAll(['en', 'hi', 'es', 'fr', 'de', 'ja', 'zh', 'ru']),
      );

      // Languages the model transcribes poorly are not offered at all:
      // low-resource Indic and African languages, plus Thai and Cantonese,
      // which degrade hardest on the turbo variant.
      final codes = speechLanguageOptions
          .map((language) => language.code)
          .toSet();
      for (final unsupported in [
        'mr',
        'bn',
        'ta',
        'te',
        'ne',
        'sw',
        'yo',
        'la',
        'th',
        'yue',
      ]) {
        expect(
          codes,
          isNot(contains(unsupported)),
          reason: '$unsupported should not be user-visible',
        );
      }
    });

    test('stays a curated list, not the full Whisper catalog', () {
      expect(speechLanguageOptions.length, inInclusiveRange(25, 40));
    });

    test('has unique language codes and labels', () {
      final codes = speechLanguageOptions.map((language) => language.code);
      final labels = speechLanguageOptions.map((language) => language.label);

      expect(codes.toSet(), hasLength(speechLanguageOptions.length));
      expect(labels.toSet(), hasLength(speechLanguageOptions.length));
    });

    test('falls back to auto when a stored code is no longer offered', () {
      expect(speechLanguageOptionForCode('mr'), isNull);
      expect(speechLanguageOptionForCode('hi')?.label, 'Hindi');
    });
  });
}
