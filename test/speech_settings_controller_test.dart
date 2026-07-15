import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';

void main() {
  group('speechLanguageOptions', () {
    test('offers exactly the languages with a validated bundled model', () {
      expect(speechLanguageOptions.map((language) => language.code).toList(), [
        'en',
        'hi',
        'hinglish',
      ]);
      expect(speechLanguageOptions.map((language) => language.label).toList(), [
        'English',
        'Hindi',
        'Hinglish',
      ]);
    });

    test('does not offer auto detection or unsupported languages', () {
      for (final unsupported in ['auto', 'mr', 'bn', 'ta', 'es', 'fr', 'zh']) {
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

      await controller.selectLanguage('hinglish');
      expect(controller.languageCode, 'hinglish');
    });
  });
}
