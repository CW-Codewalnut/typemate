import 'dart:convert';
import 'dart:io';

abstract interface class MicrophoneSettingsStore {
  Future<String?> loadSelectedMicrophoneName();
  Future<void> saveSelectedMicrophoneName(String name);
}

class NoopMicrophoneSettingsStore implements MicrophoneSettingsStore {
  const NoopMicrophoneSettingsStore();

  @override
  Future<String?> loadSelectedMicrophoneName() async => null;

  @override
  Future<void> saveSelectedMicrophoneName(String name) async {}
}

class FileMicrophoneSettingsStore implements MicrophoneSettingsStore {
  const FileMicrophoneSettingsStore({required this.file});

  final File file;

  @override
  Future<String?> loadSelectedMicrophoneName() async {
    if (!await file.exists()) {
      return null;
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded case {'selectedMicrophoneName': final String name}) {
      return name.trim().isEmpty ? null : name;
    }

    return null;
  }

  @override
  Future<void> saveSelectedMicrophoneName(String name) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'selectedMicrophoneName': name}),
      flush: true,
    );
  }
}
