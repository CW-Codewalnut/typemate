import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the splash logo before revealing the shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      DictationFlowApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
        sttEngine: MockSttEngine(),
        splashDuration: const Duration(milliseconds: 400),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('splash-logo')), findsOneWidget);
    expect(find.text('Speech history'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('splash-logo')), findsNothing);
    expect(find.text('Speech history'), findsOneWidget);
  });

  testWidgets('shuts down disposable engines when the app closes', (
    tester,
  ) async {
    final engine = ShutdownTrackingSttEngine();
    await tester.pumpWidget(
      DictationFlowApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
        sttEngine: engine,
        splashDuration: Duration.zero,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(const SizedBox.shrink());

    expect(engine.shutdownCalls, 1);
  });

  testWidgets('renders the desktop dictation shell', (tester) async {
    await tester.pumpWidget(
      DictationFlowApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
        sttEngine: MockSttEngine(),
        splashDuration: Duration.zero,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Speech history'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Prepare local engine'), findsNothing);

    final context = tester.element(find.text('Speech history'));
    expect(
      Theme.of(context).textTheme.bodyMedium?.fontFamilyFallback,
      contains('Nirmala UI'),
    );
  });
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => const [];
}

class ShutdownTrackingSttEngine extends MockSttEngine
    implements DisposableSttEngine {
  int shutdownCalls = 0;

  @override
  Future<void> shutdown() async {
    shutdownCalls += 1;
  }
}
