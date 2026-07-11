import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/audio/audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/platform/mock_platform_bridge.dart';
import 'package:typemate/src/stt/stt_engine.dart';

void main() {
  test('registers global hold shortcut and reports ready status', () async {
    final registrar = FakeHoldShortcutRegistrar();
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
    );

    await controller.register();

    expect(registrar.isRegistered, isTrue);
    expect(controller.isRegistered, isTrue);
    expect(
      controller.statusMessage,
      'Global shortcut ready: hold Ctrl+Alt+Space.',
    );
  });

  test('press starts listening and release inserts transcript', () async {
    final platformBridge = MockPlatformBridge();
    final recorder = FakeAudioRecorder();
    final registrar = FakeHoldShortcutRegistrar();
    final dictationController = createDictationController(
      platformBridge: platformBridge,
      recorder: recorder,
    );
    final shortcutController = HoldShortcutController(
      dictationController: dictationController,
      registrar: registrar,
    );

    await shortcutController.register();
    await registrar.press();

    expect(shortcutController.isPressed, isTrue);
    expect(recorder.startCount, 1);
    expect(platformBridge.overlayVisible, isTrue);

    await registrar.release();

    expect(shortcutController.isPressed, isFalse);
    expect(recorder.stopCount, 1);
    expect(platformBridge.overlayVisible, isFalse);
    expect(platformBridge.lastInsertedText, 'shortcut transcript');
  });

  test('ignores repeated key-down events while held', () async {
    final recorder = FakeAudioRecorder();
    final registrar = FakeHoldShortcutRegistrar();
    final shortcutController = HoldShortcutController(
      dictationController: createDictationController(recorder: recorder),
      registrar: registrar,
    );

    await shortcutController.register();
    await registrar.press();
    await registrar.press();

    expect(recorder.startCount, 1);
  });
}

DictationController createDictationController({
  MockPlatformBridge? platformBridge,
  FakeAudioRecorder? recorder,
}) {
  return DictationController(
    platformBridge: platformBridge ?? MockPlatformBridge(),
    sttEngine: FakeSttEngine(),
    audioRecorder: recorder ?? FakeAudioRecorder(),
  );
}

class FakeHoldShortcutRegistrar implements HoldShortcutRegistrar {
  ShortcutCallback? onPressed;
  ShortcutCallback? onReleased;
  bool isRegistered = false;

  @override
  Future<void> registerHoldShortcut({
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    this.onPressed = onPressed;
    this.onReleased = onReleased;
    isRegistered = true;
  }

  @override
  Future<void> unregisterHoldShortcut() async {
    isRegistered = false;
  }

  Future<void> press() async => onPressed!();
  Future<void> release() async => onReleased!();
}

class FakeAudioRecorder implements AudioRecorder {
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<AudioRecording> stop() async {
    stopCount += 1;
    return const AudioRecording(
      path: 'build/test.wav',
      duration: Duration(seconds: 1),
    );
  }
}

class FakeSttEngine implements SttEngine {
  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) async =>
      'shortcut transcript';
}
