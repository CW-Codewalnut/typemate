import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';

class MemorySpeechSettingsStore implements SpeechSettingsStore {
  SpeechSettingsSnapshot? saved;

  @override
  Future<SpeechSettingsSnapshot> load() async =>
      saved ?? const SpeechSettingsSnapshot(languageCode: 'en');

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async => saved = snapshot;
}

void main() {
  group('speechLanguageOptions', () {
    test('leads with the primary languages', () {
      expect(
        speechLanguageOptions.take(3).map((language) => language.code).toList(),
        ['en', 'hi', 'hinglish'],
      );
    });

    test('offers every language that has a dedicated engine', () {
      final codes = speechLanguageOptions
          .map((language) => language.code)
          .toSet();

      expect(codes, containsAll(parakeetLanguageCodes));
      expect(
        codes,
        containsAll(whisperServerLanguages.map((language) => language.code)),
      );
      expect(
        codes,
        hasLength(parakeetLanguageCodes.length + whisperServerLanguages.length),
        reason: 'every visible language must have a validated model',
      );
    });

    test('does not offer auto detection or unsupported languages', () {
      for (final unsupported in [
        'auto',
        'bn',
        'gu',
        'kn',
        'mr',
        'te',
        'ml',
        'pa',
        'ur',
        'ja',
        'ar',
      ]) {
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
      await controller.selectLanguage('bn');
      expect(controller.languageCode, 'en');

      await controller.selectLanguage('ta');
      expect(controller.languageCode, 'ta');
    });

    test('noise suppression is on by default', () {
      expect(SpeechSettingsController().noiseSuppressionEnabled, isTrue);
    });

    test(
      'persists the noise suppression toggle alongside the language',
      () async {
        final store = MemorySpeechSettingsStore();
        final controller = SpeechSettingsController(store: store);
        await controller.selectLanguage('hi');

        await controller.setNoiseSuppressionEnabled(false);

        expect(controller.noiseSuppressionEnabled, isFalse);
        expect(store.saved?.noiseSuppressionEnabled, isFalse);
        expect(store.saved?.languageCode, 'hi');

        await controller.setNoiseSuppressionEnabled(true);
        expect(store.saved?.noiseSuppressionEnabled, isTrue);
        expect(store.saved?.languageCode, 'hi');
      },
    );

    test('load restores the persisted noise suppression state', () async {
      final store = MemorySpeechSettingsStore()
        ..saved = const SpeechSettingsSnapshot(
          languageCode: 'ta',
          noiseSuppressionEnabled: false,
        );
      final controller = SpeechSettingsController(store: store);

      await controller.load();

      expect(controller.languageCode, 'ta');
      expect(controller.noiseSuppressionEnabled, isFalse);
    });
  });

  group('FileSpeechSettingsStore', () {
    late Directory tempDirectory;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync('typemate-speech');
    });

    tearDown(() {
      tempDirectory.deleteSync(recursive: true);
    });

    File settingsFile() => File('${tempDirectory.path}/speech-settings.json');

    test('round-trips a disabled noise suppression toggle', () async {
      final store = FileSpeechSettingsStore(file: settingsFile());

      await store.save(
        const SpeechSettingsSnapshot(
          languageCode: 'hi',
          noiseSuppressionEnabled: false,
        ),
      );
      final loaded = await store.load();

      expect(loaded.languageCode, 'hi');
      expect(loaded.noiseSuppressionEnabled, isFalse);
    });

    test('settings written before the toggle existed read as on', () async {
      settingsFile().writeAsStringSync('{"languageCode":"ta"}');
      final store = FileSpeechSettingsStore(file: settingsFile());

      final loaded = await store.load();

      expect(loaded.languageCode, 'ta');
      expect(loaded.noiseSuppressionEnabled, isTrue);
    });
  });
}
