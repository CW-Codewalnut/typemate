import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/microphone_audio_recorder_factory.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/hold_shortcut_controller.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';

/// One fake microphone so the app always has a selectable device; the home
/// screen auto-selects the first discovered microphone.
class FakeMicrophoneDiscovery implements MicrophoneDiscovery {
  static const microphoneName = 'CI test microphone';

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => const [
    MicrophoneDevice(name: microphoneName),
  ];
}

/// In-memory recorder: CI runners have no microphone, and the loop under
/// test is shortcut -> record -> transcribe -> insert, not audio capture.
class FakeAudioRecorder implements AudioRecorder {
  bool isRecording = false;

  @override
  Future<void> start() async {
    isRecording = true;
  }

  @override
  Future<AudioRecording> stop() async {
    isRecording = false;
    // An empty path means there is no WAV on disk to discard.
    return const AudioRecording(
      path: '',
      duration: Duration(milliseconds: 1200),
    );
  }
}

class FakeAudioRecorderFactory implements AudioRecorderFactory {
  final List<FakeAudioRecorder> createdRecorders = [];

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    final recorder = FakeAudioRecorder();
    createdRecorders.add(recorder);
    return recorder;
  }
}

/// Registrar the test drives directly, standing in for the OS-global
/// hold-to-talk key hook.
class TestHoldShortcutRegistrar implements HoldShortcutRegistrar {
  ShortcutCallback? _onPressed;
  ShortcutCallback? _onReleased;
  HoldShortcutOption? registeredShortcut;

  bool get isRegistered => _onPressed != null;

  @override
  Future<void> registerHoldShortcut({
    required HoldShortcutOption shortcut,
    required ShortcutCallback onPressed,
    required ShortcutCallback onReleased,
  }) async {
    registeredShortcut = shortcut;
    _onPressed = onPressed;
    _onReleased = onReleased;
  }

  @override
  Future<void> unregisterHoldShortcut() async {
    registeredShortcut = null;
    _onPressed = null;
    _onReleased = null;
  }

  Future<void> pressShortcut() => _onPressed!.call();

  Future<void> releaseShortcut() => _onReleased!.call();
}

/// Deterministic transcription so the test can assert the exact text that
/// must land in the focused field and in history.
class FakeSttEngine implements SttEngine {
  FakeSttEngine({required this.transcript});

  final String transcript;
  bool prepared = false;
  int transcribeCalls = 0;

  @override
  Future<bool> isReady() async => prepared;

  @override
  Future<void> prepare() async {
    prepared = true;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    transcribeCalls += 1;
    return transcript;
  }
}
