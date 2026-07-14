import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class SpeechLanguageOption {
  const SpeechLanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}

class SpeechModelOption {
  const SpeechModelOption({
    required this.id,
    required this.label,
    required this.languageCode,
    required this.description,
  });

  final String id;
  final String label;
  final String languageCode;
  final String description;
}

const speechLanguageOptions = [
  SpeechLanguageOption(code: 'en', label: 'English'),
  SpeechLanguageOption(code: 'hi', label: 'Hindi'),
  SpeechLanguageOption(code: 'multi', label: 'Multilingual'),
];

const speechModelOptions = [
  SpeechModelOption(
    id: 'tiny-en',
    label: 'Tiny English',
    languageCode: 'en',
    description: 'Fast English model for lightweight local dictation.',
  ),
  SpeechModelOption(
    id: 'base-en',
    label: 'Base English',
    languageCode: 'en',
    description: 'Balanced English model for daily typing.',
  ),
  SpeechModelOption(
    id: 'base-hi',
    label: 'Base Hindi',
    languageCode: 'hi',
    description: 'Hindi-focused local dictation model.',
  ),
  SpeechModelOption(
    id: 'base-multilingual',
    label: 'Base Multilingual',
    languageCode: 'multi',
    description: 'General multilingual model when you switch languages.',
  ),
];

abstract interface class SpeechSettingsStore {
  Future<SpeechSettingsSnapshot> load();
  Future<void> save(SpeechSettingsSnapshot snapshot);
}

class SpeechSettingsSnapshot {
  const SpeechSettingsSnapshot({
    required this.languageCode,
    required this.modelId,
  });

  final String languageCode;
  final String modelId;
}

class NoopSpeechSettingsStore implements SpeechSettingsStore {
  const NoopSpeechSettingsStore();

  @override
  Future<SpeechSettingsSnapshot> load() async =>
      const SpeechSettingsSnapshot(languageCode: 'en', modelId: 'tiny-en');

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async {}
}

class FileSpeechSettingsStore implements SpeechSettingsStore {
  const FileSpeechSettingsStore({required this.file});

  final File file;

  @override
  Future<SpeechSettingsSnapshot> load() async {
    if (!await file.exists()) {
      return const SpeechSettingsSnapshot(
        languageCode: 'en',
        modelId: 'tiny-en',
      );
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded case {
      'languageCode': final String languageCode,
      'modelId': final String modelId,
    }) {
      return SpeechSettingsSnapshot(
        languageCode: _knownLanguageCode(languageCode),
        modelId: _knownModelId(modelId),
      );
    }

    return const SpeechSettingsSnapshot(languageCode: 'en', modelId: 'tiny-en');
  }

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'languageCode': snapshot.languageCode,
        'modelId': snapshot.modelId,
      }),
      flush: true,
    );
  }

  static String _knownLanguageCode(String code) =>
      speechLanguageOptions.any((option) => option.code == code) ? code : 'en';
  static String _knownModelId(String id) =>
      speechModelOptions.any((option) => option.id == id) ? id : 'tiny-en';
}

class SpeechSettingsController extends ChangeNotifier {
  SpeechSettingsController({this.store = const NoopSpeechSettingsStore()});

  final SpeechSettingsStore store;

  String _languageCode = 'en';
  String _modelId = 'tiny-en';

  String get languageCode => _languageCode;
  String get modelId => _modelId;

  List<SpeechModelOption> get availableModels => speechModelOptions
      .where(
        (model) =>
            model.languageCode == _languageCode ||
            model.languageCode == 'multi',
      )
      .toList(growable: false);

  SpeechModelOption get selectedModel => speechModelOptions.firstWhere(
    (model) => model.id == _modelId,
    orElse: () => speechModelOptions.first,
  );

  Future<void> load() async {
    final snapshot = await store.load();
    _languageCode = snapshot.languageCode;
    _modelId = _modelAllowedForLanguage(snapshot.modelId, _languageCode)
        ? snapshot.modelId
        : availableModels.first.id;
    notifyListeners();
  }

  Future<void> selectLanguage(String languageCode) async {
    if (!speechLanguageOptions.any((option) => option.code == languageCode)) {
      return;
    }

    _languageCode = languageCode;
    if (!_modelAllowedForLanguage(_modelId, _languageCode)) {
      _modelId = availableModels.first.id;
    }
    notifyListeners();
    await _save();
  }

  Future<void> selectModel(String modelId) async {
    if (!_modelAllowedForLanguage(modelId, _languageCode)) {
      return;
    }

    _modelId = modelId;
    notifyListeners();
    await _save();
  }

  bool _modelAllowedForLanguage(String modelId, String languageCode) {
    return speechModelOptions.any(
      (model) =>
          model.id == modelId &&
          (model.languageCode == languageCode || model.languageCode == 'multi'),
    );
  }

  Future<void> _save() => store.save(
    SpeechSettingsSnapshot(languageCode: _languageCode, modelId: _modelId),
  );
}
