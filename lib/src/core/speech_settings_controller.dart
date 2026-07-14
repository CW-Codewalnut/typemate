import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class SpeechLanguageOption {
  const SpeechLanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}

const speechLanguageOptions = [
  SpeechLanguageOption(code: 'auto', label: 'Auto'),
  SpeechLanguageOption(code: 'af', label: 'Afrikaans'),
  SpeechLanguageOption(code: 'am', label: 'Amharic'),
  SpeechLanguageOption(code: 'ar', label: 'Arabic'),
  SpeechLanguageOption(code: 'as', label: 'Assamese'),
  SpeechLanguageOption(code: 'az', label: 'Azerbaijani'),
  SpeechLanguageOption(code: 'ba', label: 'Bashkir'),
  SpeechLanguageOption(code: 'be', label: 'Belarusian'),
  SpeechLanguageOption(code: 'bg', label: 'Bulgarian'),
  SpeechLanguageOption(code: 'bn', label: 'Bengali'),
  SpeechLanguageOption(code: 'bo', label: 'Tibetan'),
  SpeechLanguageOption(code: 'br', label: 'Breton'),
  SpeechLanguageOption(code: 'bs', label: 'Bosnian'),
  SpeechLanguageOption(code: 'ca', label: 'Catalan'),
  SpeechLanguageOption(code: 'cs', label: 'Czech'),
  SpeechLanguageOption(code: 'cy', label: 'Welsh'),
  SpeechLanguageOption(code: 'da', label: 'Danish'),
  SpeechLanguageOption(code: 'de', label: 'German'),
  SpeechLanguageOption(code: 'el', label: 'Greek'),
  SpeechLanguageOption(code: 'en', label: 'English'),
  SpeechLanguageOption(code: 'es', label: 'Spanish'),
  SpeechLanguageOption(code: 'et', label: 'Estonian'),
  SpeechLanguageOption(code: 'eu', label: 'Basque'),
  SpeechLanguageOption(code: 'fa', label: 'Persian'),
  SpeechLanguageOption(code: 'fi', label: 'Finnish'),
  SpeechLanguageOption(code: 'fo', label: 'Faroese'),
  SpeechLanguageOption(code: 'fr', label: 'French'),
  SpeechLanguageOption(code: 'gl', label: 'Galician'),
  SpeechLanguageOption(code: 'gu', label: 'Gujarati'),
  SpeechLanguageOption(code: 'ha', label: 'Hausa'),
  SpeechLanguageOption(code: 'haw', label: 'Hawaiian'),
  SpeechLanguageOption(code: 'he', label: 'Hebrew'),
  SpeechLanguageOption(code: 'hi', label: 'Hindi'),
  SpeechLanguageOption(code: 'hr', label: 'Croatian'),
  SpeechLanguageOption(code: 'ht', label: 'Haitian Creole'),
  SpeechLanguageOption(code: 'hu', label: 'Hungarian'),
  SpeechLanguageOption(code: 'hy', label: 'Armenian'),
  SpeechLanguageOption(code: 'id', label: 'Indonesian'),
  SpeechLanguageOption(code: 'is', label: 'Icelandic'),
  SpeechLanguageOption(code: 'it', label: 'Italian'),
  SpeechLanguageOption(code: 'ja', label: 'Japanese'),
  SpeechLanguageOption(code: 'jw', label: 'Javanese'),
  SpeechLanguageOption(code: 'ka', label: 'Georgian'),
  SpeechLanguageOption(code: 'kk', label: 'Kazakh'),
  SpeechLanguageOption(code: 'km', label: 'Khmer'),
  SpeechLanguageOption(code: 'kn', label: 'Kannada'),
  SpeechLanguageOption(code: 'ko', label: 'Korean'),
  SpeechLanguageOption(code: 'la', label: 'Latin'),
  SpeechLanguageOption(code: 'lb', label: 'Luxembourgish'),
  SpeechLanguageOption(code: 'ln', label: 'Lingala'),
  SpeechLanguageOption(code: 'lo', label: 'Lao'),
  SpeechLanguageOption(code: 'lt', label: 'Lithuanian'),
  SpeechLanguageOption(code: 'lv', label: 'Latvian'),
  SpeechLanguageOption(code: 'mg', label: 'Malagasy'),
  SpeechLanguageOption(code: 'mi', label: 'Maori'),
  SpeechLanguageOption(code: 'mk', label: 'Macedonian'),
  SpeechLanguageOption(code: 'ml', label: 'Malayalam'),
  SpeechLanguageOption(code: 'mn', label: 'Mongolian'),
  SpeechLanguageOption(code: 'mr', label: 'Marathi'),
  SpeechLanguageOption(code: 'ms', label: 'Malay'),
  SpeechLanguageOption(code: 'mt', label: 'Maltese'),
  SpeechLanguageOption(code: 'my', label: 'Myanmar'),
  SpeechLanguageOption(code: 'ne', label: 'Nepali'),
  SpeechLanguageOption(code: 'nl', label: 'Dutch'),
  SpeechLanguageOption(code: 'nn', label: 'Norwegian Nynorsk'),
  SpeechLanguageOption(code: 'no', label: 'Norwegian'),
  SpeechLanguageOption(code: 'oc', label: 'Occitan'),
  SpeechLanguageOption(code: 'pa', label: 'Punjabi'),
  SpeechLanguageOption(code: 'pl', label: 'Polish'),
  SpeechLanguageOption(code: 'ps', label: 'Pashto'),
  SpeechLanguageOption(code: 'pt', label: 'Portuguese'),
  SpeechLanguageOption(code: 'ro', label: 'Romanian'),
  SpeechLanguageOption(code: 'ru', label: 'Russian'),
  SpeechLanguageOption(code: 'sa', label: 'Sanskrit'),
  SpeechLanguageOption(code: 'sd', label: 'Sindhi'),
  SpeechLanguageOption(code: 'si', label: 'Sinhala'),
  SpeechLanguageOption(code: 'sk', label: 'Slovak'),
  SpeechLanguageOption(code: 'sl', label: 'Slovenian'),
  SpeechLanguageOption(code: 'sn', label: 'Shona'),
  SpeechLanguageOption(code: 'so', label: 'Somali'),
  SpeechLanguageOption(code: 'sq', label: 'Albanian'),
  SpeechLanguageOption(code: 'sr', label: 'Serbian'),
  SpeechLanguageOption(code: 'su', label: 'Sundanese'),
  SpeechLanguageOption(code: 'sv', label: 'Swedish'),
  SpeechLanguageOption(code: 'sw', label: 'Swahili'),
  SpeechLanguageOption(code: 'ta', label: 'Tamil'),
  SpeechLanguageOption(code: 'te', label: 'Telugu'),
  SpeechLanguageOption(code: 'tg', label: 'Tajik'),
  SpeechLanguageOption(code: 'th', label: 'Thai'),
  SpeechLanguageOption(code: 'tk', label: 'Turkmen'),
  SpeechLanguageOption(code: 'tl', label: 'Tagalog'),
  SpeechLanguageOption(code: 'tr', label: 'Turkish'),
  SpeechLanguageOption(code: 'tt', label: 'Tatar'),
  SpeechLanguageOption(code: 'uk', label: 'Ukrainian'),
  SpeechLanguageOption(code: 'ur', label: 'Urdu'),
  SpeechLanguageOption(code: 'uz', label: 'Uzbek'),
  SpeechLanguageOption(code: 'vi', label: 'Vietnamese'),
  SpeechLanguageOption(code: 'yi', label: 'Yiddish'),
  SpeechLanguageOption(code: 'yo', label: 'Yoruba'),
  SpeechLanguageOption(code: 'yue', label: 'Yue Chinese'),
  SpeechLanguageOption(code: 'zh', label: 'Chinese'),
];

abstract interface class SpeechSettingsStore {
  Future<SpeechSettingsSnapshot> load();
  Future<void> save(SpeechSettingsSnapshot snapshot);
}

class SpeechSettingsSnapshot {
  const SpeechSettingsSnapshot({required this.languageCode});

  final String languageCode;
}

class NoopSpeechSettingsStore implements SpeechSettingsStore {
  const NoopSpeechSettingsStore();

  @override
  Future<SpeechSettingsSnapshot> load() async =>
      const SpeechSettingsSnapshot(languageCode: 'auto');

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async {}
}

class FileSpeechSettingsStore implements SpeechSettingsStore {
  const FileSpeechSettingsStore({required this.file});

  final File file;

  @override
  Future<SpeechSettingsSnapshot> load() async {
    if (!await file.exists()) {
      return const SpeechSettingsSnapshot(languageCode: 'auto');
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded case {'languageCode': final String languageCode}) {
      return SpeechSettingsSnapshot(
        languageCode: _knownLanguageCode(languageCode),
      );
    }

    return const SpeechSettingsSnapshot(languageCode: 'auto');
  }

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'languageCode': snapshot.languageCode}),
      flush: true,
    );
  }

  static String _knownLanguageCode(String code) =>
      speechLanguageOptions.any((option) => option.code == code)
      ? code
      : 'auto';
}

class SpeechSettingsController extends ChangeNotifier {
  SpeechSettingsController({this.store = const NoopSpeechSettingsStore()});

  final SpeechSettingsStore store;

  String _languageCode = 'auto';

  String get languageCode => _languageCode;
  SpeechLanguageOption get selectedLanguage => speechLanguageOptions.firstWhere(
    (option) => option.code == _languageCode,
    orElse: () => speechLanguageOptions.first,
  );

  Future<void> load() async {
    final snapshot = await store.load();
    _languageCode = snapshot.languageCode;
    notifyListeners();
  }

  Future<void> selectLanguage(String languageCode) async {
    if (!speechLanguageOptions.any((option) => option.code == languageCode)) {
      return;
    }

    _languageCode = languageCode;
    notifyListeners();
    await _save();
  }

  Future<void> _save() =>
      store.save(SpeechSettingsSnapshot(languageCode: _languageCode));
}
