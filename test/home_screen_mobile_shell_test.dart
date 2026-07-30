import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/audio/mock_audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/dictation_history_controller.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/speech_settings_controller.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:typemate/src/features/home/home_screen.dart';
import 'package:typemate/src/features/settings/components/noise_suppression_panel.dart';
import 'package:typemate/src/features/settings/components/shortcut_settings_panel.dart';

class _NoMicrophones implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => const [];
}

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required bool showDictationTab,
  }) async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
      audioRecorder: MockAudioRecorder(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          controller: controller,
          historyController: DictationHistoryController(),
          microphoneController: MicrophoneSettingsController(
            discovery: _NoMicrophones(),
          ),
          speechSettingsController: SpeechSettingsController(),
          showDictationTab: showDictationTab,
          languageOptions: showDictationTab
              ? androidSpeechLanguageOptions
              : speechLanguageOptions,
          showNoiseSuppression: !showDictationTab,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('mobile shell leads with the Dictate tab', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, showDictationTab: true);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Dictate'), findsWidgets);
    expect(find.byKey(const Key('hold-to-dictate-button')), findsOneWidget);
  });

  testWidgets('desktop shell keeps its three destinations', (tester) async {
    await pumpHome(tester, showDictationTab: false);

    expect(find.text('Dictate'), findsNothing);
  });

  testWidgets('mobile settings hide the desktop-only panels', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, showDictationTab: true);
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ShortcutSettingsPanel), findsNothing);
    expect(find.byType(NoiseSuppressionPanel), findsNothing);
    expect(find.byKey(const Key('quit-typemate')), findsNothing);
  });
}
