import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';

void main() {
  group('speechLanguageOptions', () {
    test('leads with the primary languages', () {
      expect(
        speechLanguageOptions.take(3).map((language) => language.code).toList(),
        ['en', 'hi', 'hinglish'],
      );
    });

    test('offers every Parakeet language plus Hindi and Hinglish', () {
      final codes = speechLanguageOptions
          .map((language) => language.code)
          .toSet();

      expect(codes, containsAll(parakeetLanguageCodes));
      expect(codes, contains('hi'));
      expect(codes, contains('hinglish'));
      expect(
        codes,
        hasLength(parakeetLanguageCodes.length + 2),
        reason: 'every visible language must have a validated model',
      );
    });

    test('does not offer auto detection or unsupported languages', () {
      for (final unsupported in ['auto', 'mr', 'bn', 'ta', 'zh', 'ja', 'ar']) {
        expect(
          speechLanguageOptionForCode(unsupported),
          isNull,
          reason: '$unsupported should not be user-visible',
        );
      }
    });

    test('has unique language codes and labels', () {
      final codes = speechLanguageOptions.map((language) => language.code);
      final labels = speechLanguageOptions.map((language) => language.label);

      expect(codes.toSet(), hasLength(speechLanguageOptions.length));
      expect(labels.toSet(), hasLength(speechLanguageOptions.length));
    });
  });

  group('SpeechSettingsController', () {
    test('defaults to English', () {
      final controller = SpeechSettingsController();
      expect(controller.languageCode, 'en');
      expect(controller.selectedLanguage.label, 'English');
    });

    test('ignores selection of languages that are not offered', () async {
      final controller = SpeechSettingsController();
      await controller.selectLanguage('mr');
      expect(controller.languageCode, 'en');

      await controller.selectLanguage('de');
      expect(controller.languageCode, 'de');
    });
  });
}
