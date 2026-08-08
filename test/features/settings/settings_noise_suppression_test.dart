import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/microphone_settings_store.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';
import 'package:typemate/src/features/settings/settings_page.dart';

class _FakeDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => const [];
}

class _MemoryMicStore implements MicrophoneSettingsStore {
  String? saved;
  @override
  Future<String?> loadSelectedMicrophoneName() async => saved;
  @override
  Future<void> saveSelectedMicrophoneName(String name) async => saved = name;
}

class _MemorySpeechStore implements SpeechSettingsStore {
  SpeechSettingsSnapshot? saved;

  @override
  Future<SpeechSettingsSnapshot> load() async =>
      saved ?? const SpeechSettingsSnapshot(languageCode: 'en');

  @override
  Future<void> save(SpeechSettingsSnapshot snapshot) async => saved = snapshot;
}

void main() {
  setUpAll(() {
    // The version label calls PackageInfo.fromPlatform(), whose real
    // implementation does IO that never completes under the test binding.
    PackageInfo.setMockInitialValues(
      appName: 'typemate',
      packageName: 'typemate',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
      installTime: null,
      updateTime: null,
    );
  });

  testWidgets('the noise suppression toggle flips and persists the setting', (
    tester,
  ) async {
    final store = _MemorySpeechStore();
    final controller = SpeechSettingsController(store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          microphoneController: MicrophoneSettingsController(
            discovery: _FakeDiscovery(),
            store: _MemoryMicStore(),
          ),
          speechSettingsController: controller,
        ),
      ),
    );
    await tester.pump();

    final toggle = find.byKey(const Key('noise-suppression-toggle'));
    expect(toggle, findsOneWidget);
    // Suppression ships on; the toggle exists to switch it off.
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();

    expect(controller.noiseSuppressionEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(store.saved?.noiseSuppressionEnabled, isFalse);
  });
}
