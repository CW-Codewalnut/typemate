import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/microphone_settings_store.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
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

  Widget page({Future<void> Function()? onQuitRequested}) {
    return MaterialApp(
      home: SettingsPage(
        microphoneController: MicrophoneSettingsController(
          discovery: _FakeDiscovery(),
          store: _MemoryMicStore(),
        ),
        speechSettingsController: SpeechSettingsController(
          store: const NoopSpeechSettingsStore(),
        ),
        onQuitRequested: onQuitRequested,
      ),
    );
  }

  testWidgets('quit action shuts the app down via the callback', (
    tester,
  ) async {
    var quitRequested = false;
    await tester.pumpWidget(
      page(onQuitRequested: () async => quitRequested = true),
    );
    await tester.pump();

    final quitButton = find.byKey(const Key('quit-typemate'));
    expect(quitButton, findsOneWidget);

    await tester.ensureVisible(quitButton);
    await tester.tap(quitButton);
    await tester.pump();

    expect(quitRequested, isTrue);
  });

  testWidgets('no quit panel without a quit handler', (tester) async {
    await tester.pumpWidget(page());
    await tester.pump();

    expect(find.byKey(const Key('quit-typemate')), findsNothing);
  });
}
