import 'package:dictation_flow/src/core/dictation_controller.dart';
import 'package:dictation_flow/src/models/dictation_state.dart';
import 'package:dictation_flow/src/platform/mock_platform_bridge.dart';
import 'package:dictation_flow/src/stt/mock_stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepare marks the local speech engine as ready', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: MockSttEngine(),
    );

    await controller.prepare();

    expect(controller.phase, DictationPhase.idle);
    expect(controller.statusMessage, contains('Ready'));
  });

  test('start and stop dictation inserts transcript', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: MockSttEngine(),
    );

    await controller.startListening();
    expect(controller.phase, DictationPhase.listening);
    expect(platformBridge.overlayVisible, isTrue);

    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(platformBridge.overlayVisible, isFalse);
    expect(controller.latestTranscript, isNotEmpty);
    expect(platformBridge.lastInsertedText, controller.latestTranscript);
  });
}
