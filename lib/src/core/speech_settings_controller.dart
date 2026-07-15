import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/speech_language_options.dart';

export '../models/speech_language_options.dart';

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
      const SpeechSettingsSnapshot(languageCode: 'en');

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async {}
}

class FileSpeechSettingsStore implements SpeechSettingsStore {
  const FileSpeechSettingsStore({required this.file});

  final File file;

  @override
  Future<SpeechSettingsSnapshot> load() async {
    if (!await file.exists()) {
      return const SpeechSettingsSnapshot(languageCode: 'en');
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded case {'languageCode': final String languageCode}) {
      return SpeechSettingsSnapshot(
        languageCode: _knownLanguageCode(languageCode),
      );
    }

    return const SpeechSettingsSnapshot(languageCode: 'en');
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
      speechLanguageOptionForCode(code) != null ? code : 'en';
}

class SpeechSettingsController extends ChangeNotifier {
  SpeechSettingsController({this.store = const NoopSpeechSettingsStore()});

  final SpeechSettingsStore store;

  String _languageCode = 'en';

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
