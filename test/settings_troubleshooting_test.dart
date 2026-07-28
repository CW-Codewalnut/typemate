import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/diagnostics/diagnostic_reporter.dart';
import 'package:typemate/src/core/diagnostics/telemetry_controller.dart';
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

class _NullSink implements TelemetrySink {
  @override
  void reportFailure(String area, String kind, String message) {}
}

class _MemoryTelemetryStore implements TelemetrySettingsStore {
  TelemetrySettingsSnapshot? saved;

  @override
  Future<TelemetrySettingsSnapshot> load() async =>
      saved ?? const TelemetrySettingsSnapshot();

  @override
  Future<void> save(TelemetrySettingsSnapshot snapshot) async =>
      saved = snapshot;
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

  Widget buildSettings({
    TelemetryController? telemetryController,
    String? logsDirectoryPath,
    Future<void> Function(String path)? onOpenLogsFolder,
  }) {
    return MaterialApp(
      home: SettingsPage(
        microphoneController: MicrophoneSettingsController(
          discovery: _FakeDiscovery(),
          store: _MemoryMicStore(),
        ),
        speechSettingsController: SpeechSettingsController(),
        telemetryController: telemetryController,
        logsDirectoryPath: logsDirectoryPath,
        onOpenLogsFolder: onOpenLogsFolder,
      ),
    );
  }

  testWidgets('the log folder button opens the diagnostics directory', (
    tester,
  ) async {
    String? openedPath;
    await tester.pumpWidget(
      buildSettings(
        logsDirectoryPath: r'C:\Users\jane\AppData\Roaming\TypeMate\logs',
        onOpenLogsFolder: (path) async => openedPath = path,
      ),
    );
    await tester.pump();

    final button = find.byKey(const Key('open-log-folder'));
    expect(button, findsOneWidget);
    // No telemetry controller: the consent toggle must not render.
    expect(find.byKey(const Key('telemetry-toggle')), findsNothing);

    await tester.ensureVisible(button);
    await tester.tap(button);

    expect(openedPath, r'C:\Users\jane\AppData\Roaming\TypeMate\logs');
  });

  testWidgets('the telemetry toggle flips and persists the consent', (
    tester,
  ) async {
    final store = _MemoryTelemetryStore();
    final controller = TelemetryController(
      store: store,
      dsn: 'https://x@example.ingest.sentry.io/1',
      telemetrySink: _NullSink(),
      startTelemetry: () async {},
      stopTelemetry: () async {},
    );
    await controller.load();
    await tester.pumpWidget(buildSettings(telemetryController: controller));
    await tester.pump();

    final toggle = find.byKey(const Key('telemetry-toggle'));
    expect(toggle, findsOneWidget);
    // Error reporting ships on; the toggle exists to switch it off.
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();

    expect(controller.enabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(store.saved?.errorReportingEnabled, isFalse);
  });

  testWidgets('no troubleshooting panel without logs or telemetry', (
    tester,
  ) async {
    await tester.pumpWidget(buildSettings());
    await tester.pump();

    expect(find.text('Troubleshooting'), findsNothing);
    expect(find.byKey(const Key('open-log-folder')), findsNothing);
  });
}
