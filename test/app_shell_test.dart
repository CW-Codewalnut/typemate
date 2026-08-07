import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/stt/mock_stt_engine.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens straight to the shell (no in-app splash)', (tester) async {
    await tester.pumpWidget(
      TypeMateApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
        sttEngine: MockSttEngine(),
      ),
    );
    await tester.pump();

    // The native OS splash covers startup; the shell is the first Flutter
    // frame, with no manufactured splash in between.
    expect(find.text('Dictate'), findsWidgets);

    // Let the engine-prepare timer fire so none is left pending.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shuts down disposable engines when the app closes', (
    tester,
  ) async {
    final engine = ShutdownTrackingSttEngine();
    await tester.pumpWidget(
      TypeMateApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
        sttEngine: engine,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(const SizedBox.shrink());

    expect(engine.shutdownCalls, 1);
  });

  testWidgets('renders the desktop dictation shell', (tester) async {
    await tester.pumpWidget(
      TypeMateApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
        sttEngine: MockSttEngine(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Dictate'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Prepare local engine'), findsNothing);

    final context = tester.element(find.text('Dictate').last);
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
