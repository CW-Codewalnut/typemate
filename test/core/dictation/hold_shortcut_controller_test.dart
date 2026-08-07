import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';

void main() {
  test('registers Ctrl+Win hold as the safe default shortcut', () async {
    final registrar = FakeHoldShortcutRegistrar();
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
    );

    await controller.register();

    expect(registrar.isRegistered, isTrue);
    expect(controller.isRegistered, isTrue);
    expect(controller.statusMessage, 'Global shortcut ready: hold Ctrl+Win.');
    expect(registrar.shortcut?.id, defaultHoldShortcutId);
    expect(registrar.shortcut?.virtualKeyCodes, [0x11, 0x5B]);
  });

  test('holdShortcutRejectionReason accepts and refuses the right shapes', () {
    // Accepted: every shape the picker offers.
    for (final option in holdShortcutOptions) {
      expect(
        holdShortcutRejectionReason(option.virtualKeyCodes),
        isNull,
        reason: '${option.label} is offered, so it must be usable',
      );
    }

    // Refused: a bare key binds dictation to it system-wide, and the user
    // cannot type their way to Settings to undo it.
    expect(holdShortcutRejectionReason([0x41]), isNotNull); // A
    expect(holdShortcutRejectionReason([]), isNotNull);
    // Two keys but no modifier is just as unusable.
    expect(holdShortcutRejectionReason([0x41, 0x42]), isNotNull); // A+B
    // Combinations the OS owns.
    expect(holdShortcutRejectionReason([0x11, 0x43]), isNotNull); // Ctrl+C
    expect(holdShortcutRejectionReason([0x12, 0x09]), isNotNull); // Alt+Tab
    // A modifier plus a key is the minimum that leaves the keyboard usable.
    expect(holdShortcutRejectionReason([0x11, 0x78]), isNull); // Ctrl+F9
  });

  test('an unusable custom shortcut on disk never binds', () async {
    // A build older than the recorder's validation (or a hand-edited
    // settings file) can leave `custom:65` — the A key — persisted.
    // Validating only where shortcuts are recorded would let it load and
    // bind on every launch, which is the state the user cannot escape.
    final registrar = FakeHoldShortcutRegistrar();
    final store = MemoryHoldShortcutSettingsStore('custom:65');
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
      store: store,
    );

    await controller.register();

    expect(controller.shortcut.id, defaultHoldShortcutId);
    expect(registrar.shortcut?.id, defaultHoldShortcutId);
  });

  test('selecting an unusable shortcut leaves the current one live', () async {
    final registrar = FakeHoldShortcutRegistrar();
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
      store: MemoryHoldShortcutSettingsStore(defaultHoldShortcutId),
    );
    await controller.register();

    await controller.selectShortcutOption(customHoldShortcutOption([0x41]));

    expect(controller.shortcut.id, defaultHoldShortcutId);
    expect(registrar.shortcut?.id, defaultHoldShortcutId);
    expect(controller.statusMessage, contains('modifier'));
  });

  test('a failed re-register keeps the previous shortcut working', () async {
    // selectShortcutOption assigned the new shortcut before registering, so
    // a failure both looked like success to anyone reading `shortcut` and
    // escaped as an unhandled Future error.
    final registrar = FakeHoldShortcutRegistrar();
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
      store: MemoryHoldShortcutSettingsStore(defaultHoldShortcutId),
    );
    await controller.register();
    registrar.failNextRegister = true;

    await expectLater(
      controller.selectShortcutOption(holdShortcutOptionById('ctrl-shift-f9')),
      completes,
    );

    expect(controller.shortcut.id, defaultHoldShortcutId);
    expect(controller.statusMessage, contains('Could not apply'));
  });

  test('every offered shortcut survives a save and reload', () async {
    // legacyShortcutIds is the migration list; an id in BOTH it and the
    // picker can never persist, because loading rewrites it to the
    // default. Iterating the picker catches that, where iterating the
    // constant only ever asserts whatever the constant already says.
    for (final option in holdShortcutOptions) {
      final registrar = FakeHoldShortcutRegistrar();
      final store = MemoryHoldShortcutSettingsStore(option.id);
      final controller = HoldShortcutController(
        dictationController: createDictationController(),
        registrar: registrar,
        store: store,
      );

      await controller.register();

      expect(
        controller.shortcut.id,
        option.id,
        reason: '${option.label} must load back as itself',
      );
      expect(registrar.shortcut?.id, option.id);
    }
  });

  test('migrates old shortcuts to Ctrl+Win hold', () async {
    // An explicit list: iterating legacyShortcutIds would make this test
    // agree with the constant no matter what the constant contains.
    const retiredShortcutIds = [
      'ctrl-double-tap-hold',
      'ctrl-shift',
      'ctrl',
      'ctrl-alt-space',
      'ctrl-shift-space',
      'alt-shift-space',
    ];
    for (final legacyShortcutId in retiredShortcutIds) {
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

  test('recorded custom shortcut re-registers with the pressed keys', () async {
    final registrar = FakeHoldShortcutRegistrar();
    final store = MemoryHoldShortcutSettingsStore();
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
      store: store,
    );

    await controller.register();
    await controller.selectShortcutOption(
      customHoldShortcutOption([0x10, 0x11, 0x41]),
    );

    expect(controller.shortcut.id, 'custom:17-16-65');
    expect(controller.shortcut.label, 'Ctrl+Shift+A');
    expect(registrar.registerCount, 2);
    expect(registrar.shortcut?.virtualKeyCodes, [0x11, 0x10, 0x41]);
    expect(store.savedShortcutId, 'custom:17-16-65');
    expect(
      controller.statusMessage,
      'Global shortcut ready: hold Ctrl+Shift+A.',
    );
  });

  test('reset shortcut restores the default Ctrl+Win hold shortcut', () async {
    final registrar = FakeHoldShortcutRegistrar();
    final store = MemoryHoldShortcutSettingsStore('custom:17-16-65');
    final controller = HoldShortcutController(
      dictationController: createDictationController(),
      registrar: registrar,
      store: store,
    );

    await controller.register();
    await controller.resetShortcutToDefault();

    expect(controller.shortcut.id, defaultHoldShortcutId);
    expect(registrar.shortcut?.id, defaultHoldShortcutId);
    expect(store.savedShortcutId, defaultHoldShortcutId);
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

  /// Fails the next register only, so a test can check the recovery path
  /// puts the previous shortcut back.
  bool failNextRegister = false;

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    if (failNextRegister) {
      failNextRegister = false;
      throw StateError('registrar refused the shortcut');
    }
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
