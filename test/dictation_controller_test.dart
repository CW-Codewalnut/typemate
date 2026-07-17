import 'dart:io';

import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/models/dictation_state.dart';
import 'package:typemate/src/core/platform/platform_bridge.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
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

  test('recovers when preparing the local speech engine fails', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: ThrowingPrepareSttEngine(),
      audioRecorder: FakeAudioRecorder(),
    );

    await controller.prepare();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      'Unable to prepare local speech engine. Check the speech runtime and model file, then try again.',
    );
  });

  test('deletes the recording file after it is transcribed', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-rec');
    addTearDown(() => directory.deleteSync(recursive: true));
    final wavFile = File('${directory.path}/voice.wav')
      ..writeAsBytesSync([1, 2, 3]);
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(transcript: 'hello'),
      audioRecorder: FakeAudioRecorder(
        recording: AudioRecording(
          path: wavFile.path,
          duration: const Duration(seconds: 2),
        ),
      ),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.latestTranscript, 'hello');
    expect(wavFile.existsSync(), isFalse);
  });

  test('deletes the recording file when transcription fails', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-rec');
    addTearDown(() => directory.deleteSync(recursive: true));
    final wavFile = File('${directory.path}/voice.wav')
      ..writeAsBytesSync([1, 2, 3]);
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(
        recording: AudioRecording(
          path: wavFile.path,
          duration: const Duration(seconds: 2),
        ),
      ),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(wavFile.existsSync(), isFalse);
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
      Duration? storedDuration;
      final controller = DictationController(
        platformBridge: platformBridge,
        sttEngine: sttEngine,
        audioRecorder: audioRecorder,
        onTranscriptGenerated: (transcript, {duration = Duration.zero}) async {
          storedDuration = duration;
        },
      );

      await controller.startListening();
      await controller.stopListening();

      expect(controller.phase, DictationPhase.idle);
      expect(platformBridge.overlayVisible, isFalse);
      expect(platformBridge.transcribingOverlayCount, 1);
      expect(audioRecorder.stopped, isTrue);
      expect(sttEngine.lastRecording?.path, 'voice.wav');
      expect(controller.latestTranscript, 'Run the tests and fix the failure.');
      expect(platformBridge.lastInsertedText, controller.latestTranscript);
      expect(storedDuration, const Duration(seconds: 2));
    },
  );

  test('trims local transcript before storing and inserting it', () async {
    final platformBridge = MockPlatformBridge();
    final audioRecorder = FakeAudioRecorder();
    final sttEngine = FakeSttEngine(transcript: '  Keep this text.\n');
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.latestTranscript, 'Keep this text.');
    expect(platformBridge.lastInsertedText, 'Keep this text.');
  });

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

  test('recovers when the recorder fails to start', () async {
    final platformBridge = MockPlatformBridge();
    final sttEngine = FakeSttEngine();
    final audioRecorder = ThrowingAudioRecorder();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
    );

    await controller.startListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      'Unable to start recording. Check the microphone and its permissions, then try again.',
    );
    expect(platformBridge.overlayVisible, isFalse);
    expect(sttEngine.lastRecording, isNull);
  });

  test('recovers when the recorder fails to stop', () async {
    final platformBridge = MockPlatformBridge();
    final sttEngine = FakeSttEngine();
    final audioRecorder = ThrowingStopAudioRecorder();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      'Unable to finish recording. Check the microphone and its permissions, then try again.',
    );
    expect(platformBridge.overlayVisible, isFalse);
    expect(audioRecorder.started, isTrue);
    expect(sttEngine.lastRecording, isNull);
    expect(controller.latestTranscript, isEmpty);
  });

  test('recovers when local transcription fails', () async {
    final platformBridge = MockPlatformBridge();
    final audioRecorder = FakeAudioRecorder(
      recording: const AudioRecording(
        path: 'voice.wav',
        duration: Duration(seconds: 2),
      ),
    );
    final sttEngine = ThrowingSttEngine();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      'Unable to transcribe locally. Check the speech runtime and model file, then try again.',
    );
    expect(platformBridge.overlayVisible, isFalse);
    expect(platformBridge.lastInsertedText, isEmpty);
    expect(controller.latestTranscript, isEmpty);
  });

  test(
    'does not insert when local transcription returns no usable text',
    () async {
      final platformBridge = MockPlatformBridge();
      final audioRecorder = FakeAudioRecorder(
        recording: const AudioRecording(
          path: 'silence.wav',
          duration: Duration(seconds: 2),
        ),
      );
      final sttEngine = FakeSttEngine(transcript: '   \n  ');
      final controller = DictationController(
        platformBridge: platformBridge,
        sttEngine: sttEngine,
        audioRecorder: audioRecorder,
      );

      await controller.startListening();
      await controller.stopListening();

      expect(controller.phase, DictationPhase.idle);
      expect(controller.latestTranscript, isEmpty);
      expect(platformBridge.lastInsertedText, isEmpty);
      expect(
        controller.statusMessage,
        'Silent audio. Ready for the next dictation.',
      );
    },
  );

  test('treats whisper blank-audio markers as silent audio', () async {
    final platformBridge = MockPlatformBridge();
    final audioRecorder = FakeAudioRecorder(
      recording: const AudioRecording(
        path: 'silence.wav',
        duration: Duration(seconds: 2),
      ),
    );
    final sttEngine = FakeSttEngine(transcript: '[BLANK_AUDIO]');
    var storedTranscript = '';
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
      onTranscriptGenerated: (transcript, {duration = Duration.zero}) async {
        storedTranscript = transcript;
      },
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(controller.latestTranscript, isEmpty);
    expect(platformBridge.lastInsertedText, isEmpty);
    expect(storedTranscript, isEmpty);
    expect(
      controller.statusMessage,
      'Silent audio. Ready for the next dictation.',
    );
  });

  test('keeps question-mark transcripts visible for debugging', () async {
    final platformBridge = MockPlatformBridge();
    final audioRecorder = FakeAudioRecorder(
      recording: const AudioRecording(
        path: 'hindi.wav',
        duration: Duration(seconds: 2),
      ),
    );
    final sttEngine = FakeSttEngine(transcript: '?????');
    var storedTranscript = '';
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
      onTranscriptGenerated: (transcript, {duration = Duration.zero}) async {
        storedTranscript = transcript;
      },
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(controller.latestTranscript, '?????');
    expect(platformBridge.lastInsertedText, '?????');
    expect(storedTranscript, '?????');
    expect(
      controller.statusMessage,
      'Inserted transcript. Ready for the next dictation.',
    );
  });

  test('recovers when focused-field insertion fails', () async {
    final platformBridge = ThrowingInsertPlatformBridge();
    final audioRecorder = FakeAudioRecorder(
      recording: const AudioRecording(
        path: 'voice.wav',
        duration: Duration(seconds: 2),
      ),
    );
    final sttEngine = FakeSttEngine(transcript: 'Insert this text.');
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: sttEngine,
      audioRecorder: audioRecorder,
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      'Unable to insert text into the focused field. Copy the latest transcript manually and try again.',
    );
    expect(platformBridge.overlayVisible, isFalse);
    expect(platformBridge.insertAttempted, isTrue);
    expect(controller.latestTranscript, 'Insert this text.');
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

class ThrowingAudioRecorder implements AudioRecorder {
  @override
  Future<void> start() async {
    throw StateError('ffmpeg failed to start');
  }

  @override
  Future<AudioRecording> stop() async {
    throw StateError('should not stop when start fails');
  }
}

class ThrowingStopAudioRecorder implements AudioRecorder {
  bool started = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<AudioRecording> stop() async {
    throw StateError('ffmpeg failed to finish recording');
  }
}

class ThrowingSttEngine implements SttEngine {
  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) async {
    throw StateError('model failed');
  }
}

class ThrowingPrepareSttEngine implements SttEngine {
  @override
  Future<bool> isReady() async => false;

  @override
  Future<void> prepare() async {
    throw StateError('runtime missing');
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    throw StateError('should not transcribe when prepare fails');
  }
}

class ThrowingInsertPlatformBridge implements PlatformBridge {
  bool overlayVisible = false;
  bool insertAttempted = false;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {
    overlayVisible = true;
  }

  @override
  Future<void> showTranscribingOverlay() async {
    overlayVisible = true;
  }

  @override
  Future<void> hideListeningOverlay() async {
    overlayVisible = false;
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    insertAttempted = true;
    throw StateError('focused field unavailable');
  }

  @override
  Future<void> ensureLaunchAtStartup() async {}
}
