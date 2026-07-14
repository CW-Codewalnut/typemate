import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/audio/audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/platform/mock_platform_bridge.dart';
import 'package:typemate/src/stt/stt_engine.dart';

void main() {
  test(
    'registers double-tap Ctrl then hold as the safe default shortcut',
    () async {
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
        'Global shortcut ready: double-tap Ctrl, then hold Ctrl to dictate.',
      );
      expect(registrar.shortcut?.id, defaultHoldShortcutId);
      expect(registrar.shortcut?.virtualKeyCodes, [0x11]);
    },
  );

  test('migrates old shortcuts to double-tap Ctrl then hold', () async {
    for (final legacyShortcutId in legacyShortcutIds) {
      final registrar = FakeHoldShortcutRegistrar();
      final store = MemoryHoldShortcutSettingsStore(legacyShortcutId);
      final controller = HoldShortcutController(
        dictationController: createDictationController(),
        registrar: registrar,
        store: store,
      );

      await controller.register();

      expect(controller.shortcut.id, defaultHoldShortcutId);
      expect(registrar.shortcut?.id, defaultHoldShortcutId);
      expect(store.savedShortcutId, defaultHoldShortcutId);
    }
  });

  test('changing shortcut re-registers with the selected option', () async {
    final registrar = FakeHoldShortcutRegistrar();
    final store = MemoryHoldShortcutSettingsStore();
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
      store: store,
    );

    await controller.register();
    await controller.selectShortcut('ctrl-shift-f9');

    expect(controller.shortcut.id, 'ctrl-shift-f9');
    expect(registrar.registerCount, 2);
    expect(registrar.shortcut?.label, 'Ctrl+Shift+F9');
    expect(registrar.shortcut?.virtualKeyCodes, isNot(contains(0x20)));
    expect(store.savedShortcutId, 'ctrl-shift-f9');
    expect(
      controller.statusMessage,
      'Global shortcut ready: hold Ctrl+Shift+F9.',
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
  HoldShortcutOption? shortcut;
  bool isRegistered = false;
  int registerCount = 0;

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    this.shortcut = shortcut;
    this.onPressed = onPressed;
    this.onReleased = onReleased;
    isRegistered = true;
    registerCount += 1;
  }

  @override
  Future<void> unregisterHoldShortcut() async {
    isRegistered = false;
  }

  Future<void> press() async => onPressed!();
  Future<void> release() async => onReleased!();
}

class MemoryHoldShortcutSettingsStore implements HoldShortcutSettingsStore {
  MemoryHoldShortcutSettingsStore([
    this.savedShortcutId = defaultHoldShortcutId,
  ]);

  String savedShortcutId;

  @override
  Future<String> loadShortcutId() async => savedShortcutId;

  @override
  Future<void> saveShortcutId(String shortcutId) async {
    savedShortcutId = shortcutId;
  }
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
