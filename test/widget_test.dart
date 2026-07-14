import 'package:typemate/src/app.dart';
import 'package:typemate/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the desktop dictation shell', (tester) async {
    await tester.pumpWidget(
      DictationFlowApp(
        microphoneDiscovery: FakeMicrophoneDiscovery(),
        holdShortcutRegistrar: const NoopHoldShortcutRegistrar(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Speech history'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Prepare local engine'), findsNothing);
  });
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => const [];
}
