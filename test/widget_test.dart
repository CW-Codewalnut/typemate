import 'package:typemate/src/app.dart';
import 'package:typemate/src/audio/ffmpeg_microphone_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the desktop dictation shell', (tester) async {
    await tester.pumpWidget(
      DictationFlowApp(microphoneDiscovery: FakeMicrophoneDiscovery()),
    );
    await tester.pumpAndSettle();

    expect(find.text('TypeMate'), findsOneWidget);
    expect(
      find.text('Local hold to dictate for developers and heavy typers.'),
      findsOneWidget,
    );
    expect(find.text('Prepare local engine'), findsOneWidget);
  });
}

class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => const [];
}
