import 'package:dictation_flow/src/audio/audio_recorder.dart';
import 'package:dictation_flow/src/core/dictation_controller.dart';
import 'package:dictation_flow/src/models/dictation_state.dart';
import 'package:dictation_flow/src/platform/mock_platform_bridge.dart';
import 'package:dictation_flow/src/stt/stt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepare marks the local speech engine as ready', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(),
      audioRecorder: FakeAudioRecorder(),
    );

    await controller.prepare();

    expect(controller.phase, DictationPhase.idle);
    expect(controller.statusMessage, contains('Ready'));
  });

  test('startListening starts recording and shows overlay', () async {
    final platformBridge = MockPlatformBridge();
    final audioRecorder = FakeAudioRecorder();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: FakeSttEngine(),
      audioRecorder: audioRecorder,
    );

    await controller.startListening();

    expect(controller.phase, DictationPhase.listening);
    expect(platformBridge.overlayVisible, isTrue);
    expect(audioRecorder.started, isTrue);
  });

  test(
    'stopListening transcribes the stopped recording and inserts transcript',
    () async {
      final platformBridge = MockPlatformBridge();
      final audioRecorder = FakeAudioRecorder(
        recording: const AudioRecording(
          path: 'voice.wav',
          duration: Duration(seconds: 2),
        ),
      );
      final sttEngine = FakeSttEngine(
        transcript: 'Run the tests and fix the failure.',
      );
      final controller = DictationController(
        platformBridge: platformBridge,
        sttEngine: sttEngine,
        audioRecorder: audioRecorder,
      );

      await controller.startListening();
      await controller.stopListening();

      expect(controller.phase, DictationPhase.idle);
      expect(platformBridge.overlayVisible, isFalse);
      expect(audioRecorder.stopped, isTrue);
      expect(sttEngine.lastRecording?.path, 'voice.wav');
      expect(controller.latestTranscript, 'Run the tests and fix the failure.');
      expect(platformBridge.lastInsertedText, controller.latestTranscript);
    },
  );

  test('uses the recorder provided when listening starts', () async {
    final selectedRecorder = FakeAudioRecorder(
      recording: const AudioRecording(
        path: 'selected-microphone.wav',
        duration: Duration(seconds: 3),
      ),
    );
    final sttEngine = FakeSttEngine();
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: sttEngine,
      audioRecorderProvider: () => selectedRecorder,
    );

    await controller.startListening();
    await controller.stopListening();

    expect(selectedRecorder.started, isTrue);
    expect(selectedRecorder.stopped, isTrue);
    expect(sttEngine.lastRecording?.path, 'selected-microphone.wav');
  });

  test('does not start listening when no recorder is available', () async {
    final platformBridge = MockPlatformBridge();
    final sttEngine = FakeSttEngine();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorderProvider: () => null,
    );

    await controller.startListening();

    expect(controller.phase, DictationPhase.idle);
    expect(controller.statusMessage, 'Select a microphone before dictating.');
    expect(platformBridge.overlayVisible, isFalse);
    expect(sttEngine.lastRecording, isNull);
  });
}

class FakeAudioRecorder implements AudioRecorder {
  FakeAudioRecorder({
    this.recording = const AudioRecording(
      path: 'preview.wav',
      duration: Duration(milliseconds: 800),
    ),
  });

  final AudioRecording recording;
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<AudioRecording> stop() async {
    stopped = true;
    return recording;
  }
}

class FakeSttEngine implements SttEngine {
  FakeSttEngine({this.transcript = 'This is a local dictation preview.'});

  final String transcript;
  bool ready = false;
  AudioRecording? lastRecording;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<void> prepare() async {
    ready = true;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    lastRecording = recording;
    return transcript;
  }
}
