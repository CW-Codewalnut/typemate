import 'dart:async';
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

  test('keeps the recording for retry when transcription fails', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-rec');
    addTearDown(() => directory.deleteSync(recursive: true));
    final wavFile = File('${directory.path}/voice.wav')
      ..writeAsBytesSync([1, 2, 3]);
    String? failedReason;
    String? keptPath;
    Duration? failedDuration;
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(
        recording: AudioRecording(
          path: wavFile.path,
          duration: const Duration(seconds: 2),
        ),
      ),
      onTranscriptionFailed:
          (reason, {recordingPath, duration = Duration.zero}) async {
            failedReason = reason;
            keptPath = recordingPath;
            failedDuration = duration;
          },
    );

    await controller.startListening();
    await controller.stopListening();

    // The WAV moved into the failed/ folder, out of the startup purge's
    // reach, and the failure callback points at the kept copy.
    expect(wavFile.existsSync(), isFalse);
    expect(failedReason, DictationController.transcriptionFailedMessage);
    expect(failedDuration, const Duration(seconds: 2));
    expect(keptPath, isNotNull);
    expect(keptPath, contains('failed'));
    expect(File(keptPath!).existsSync(), isTrue);
    // Only the OS toast (read outside the app) points at History.
    expect(
      platformBridge.lastFailureNotification,
      DictationController.transcriptionFailedMessage +
          DictationController.retryFromHistoryHint,
    );
  });

  test('transcription timeout scales with the recording length', () {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(),
      audioRecorder: FakeAudioRecorder(),
    );

    expect(
      controller.transcribeTimeoutFor(const Duration(seconds: 5)),
      const Duration(seconds: 20),
    );
    expect(
      controller.transcribeTimeoutFor(Duration.zero),
      DictationController.defaultTranscribeTimeout,
    );
    expect(
      controller.transcribeTimeoutFor(const Duration(minutes: 10)),
      DictationController.maxTranscribeTimeout,
    );
  });

  test('retryTranscription resolves a kept recording into text', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-rec');
    addTearDown(() => directory.deleteSync(recursive: true));
    final keptFile = File('${directory.path}/kept.wav')
      ..writeAsBytesSync([1, 2, 3]);
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(transcript: '  Second time lucky.  '),
      audioRecorder: FakeAudioRecorder(),
    );

    final transcript = await controller.retryTranscription(
      keptFile.path,
      duration: const Duration(seconds: 2),
    );

    expect(transcript, 'Second time lucky.');
    expect(controller.phase, DictationPhase.idle);
    expect(controller.errorMessage, isNull);
  });

  test('retryTranscription reports a repeat failure', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
    );

    final transcript = await controller.retryTranscription('kept.wav');

    expect(transcript, isNull);
    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.errorMessage,
      DictationController.transcriptionFailedMessage,
    );
  });

  test('retryTranscription times out like a live dictation', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: HangingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
      transcribeTimeout: const Duration(milliseconds: 50),
    );

    final transcript = await controller.retryTranscription('kept.wav');

    expect(transcript, isNull);
    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.errorMessage,
      DictationController.transcriptionTimeoutMessage,
    );
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
      DictationController.failedToStartRecordingMessage,
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
      DictationController.failedToFinishRecordingMessage,
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
      DictationController.transcriptionFailedMessage,
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

  test('inserts the transcript even when storing history fails', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: FakeSttEngine(transcript: 'Saved anyway.'),
      audioRecorder: FakeAudioRecorder(),
      onTranscriptGenerated: (transcript, {duration = Duration.zero}) async {
        throw const FileSystemException('history.json is locked');
      },
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(platformBridge.lastInsertedText, 'Saved anyway.');
    expect(platformBridge.overlayVisible, isFalse);
    expect(
      controller.statusMessage,
      'Inserted transcript. Ready for the next dictation.',
    );
  });

  test('times out with an error when transcription hangs forever', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: HangingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
      transcribeTimeout: const Duration(milliseconds: 50),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      DictationController.transcriptionTimeoutMessage,
    );
    expect(
      platformBridge.lastFailureNotification,
      DictationController.transcriptionTimeoutMessage,
    );
    expect(platformBridge.overlayVisible, isFalse);
  });

  test('accepts the next dictation after a transcription timeout', () async {
    final platformBridge = MockPlatformBridge();
    var hangs = true;
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: SwitchableSttEngine(
        (recording) =>
            hangs ? Completer<String>().future : Future.value('Second try.'),
      ),
      audioRecorder: FakeAudioRecorder(),
      transcribeTimeout: const Duration(milliseconds: 50),
    );

    await controller.startListening();
    await controller.stopListening();
    expect(controller.phase, DictationPhase.idle);

    hangs = false;
    await controller.startListening();
    await controller.stopListening();

    expect(controller.latestTranscript, 'Second try.');
    expect(platformBridge.lastInsertedText, 'Second try.');
  });

  test('times out with an error when the recorder never stops', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: FakeSttEngine(),
      audioRecorder: HangingStopAudioRecorder(),
      recorderStopTimeout: const Duration(milliseconds: 50),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      controller.statusMessage,
      DictationController.failedToFinishRecordingMessage,
    );
    expect(platformBridge.overlayVisible, isFalse);
  });

  test(
    'reaches idle with an error even when the overlay bridge fails',
    () async {
      final platformBridge = FailingOverlayPlatformBridge();
      final controller = DictationController(
        platformBridge: platformBridge,
        sttEngine: ThrowingSttEngine(),
        audioRecorder: FakeAudioRecorder(),
      );

      await controller.startListening();
      await controller.stopListening();

      expect(controller.phase, DictationPhase.idle);
      expect(
        controller.statusMessage,
        DictationController.transcriptionFailedMessage,
      );
    },
  );

  test(
    'still dictates when the transcribing overlay cannot be shown',
    () async {
      final platformBridge = FailingOverlayPlatformBridge(
        failTranscribingOnly: true,
      );
      final controller = DictationController(
        platformBridge: platformBridge,
        sttEngine: FakeSttEngine(transcript: 'Overlay is optional.'),
        audioRecorder: FakeAudioRecorder(),
      );

      await controller.startListening();
      await controller.stopListening();

      expect(controller.phase, DictationPhase.idle);
      expect(platformBridge.lastInsertedText, 'Overlay is optional.');
      expect(
        controller.statusMessage,
        'Inserted transcript. Ready for the next dictation.',
      );
    },
  );

  test('hides the overlay when transcription fails', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(platformBridge.overlayVisible, isFalse);
  });

  test('posts an OS notification with the failure reason', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(
      platformBridge.lastFailureNotification,
      DictationController.transcriptionFailedMessage,
    );
  });

  test('plays the failure tone on failure and never on success', () async {
    var failurePlays = 0;
    Future<void> countingPlayer() async => failurePlays += 1;

    final failing = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
      failureSoundPlayer: countingPlayer,
    );
    await failing.startListening();
    await failing.stopListening();
    expect(failurePlays, 1);

    final succeeding = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(transcript: 'All good.'),
      audioRecorder: FakeAudioRecorder(),
      failureSoundPlayer: countingPlayer,
    );
    await succeeding.startListening();
    await succeeding.stopListening();
    expect(failurePlays, 1);
  });

  test('plays the start chime once per dictation', () async {
    var startPlays = 0;
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(transcript: 'Hello.'),
      audioRecorder: FakeAudioRecorder(),
      startSoundPlayer: () async => startPlays += 1,
    );

    await controller.startListening();
    expect(startPlays, 1);
    await controller.stopListening();
    expect(startPlays, 1);

    await controller.startListening();
    expect(startPlays, 2);
    await controller.stopListening();
  });

  test('a broken start-sound player never blocks dictation', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: FakeSttEngine(transcript: 'Still works.'),
      audioRecorder: FakeAudioRecorder(),
      startSoundPlayer: () async => throw StateError('no audio device'),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(platformBridge.lastInsertedText, 'Still works.');
  });

  test('a broken failure-sound player never blocks the failure flow', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: ThrowingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
      failureSoundPlayer: () async => throw StateError('no audio device'),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.phase, DictationPhase.idle);
    expect(
      platformBridge.lastFailureNotification,
      DictationController.transcriptionFailedMessage,
    );
  });

  test('successful dictation posts no failure notification', () async {
    final platformBridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: platformBridge,
      sttEngine: FakeSttEngine(transcript: 'All good.'),
      audioRecorder: FakeAudioRecorder(),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(platformBridge.lastFailureNotification, isEmpty);
  });

  test('keeps the failure reason until the next dictation starts', () async {
    var failing = true;
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: SwitchableSttEngine(
        (recording) => failing
            ? Future<String>.error(StateError('model failed'))
            : Future.value('Back to normal.'),
      ),
      audioRecorder: FakeAudioRecorder(),
    );
    expect(controller.errorMessage, isNull);

    await controller.startListening();
    await controller.stopListening();

    expect(
      controller.errorMessage,
      DictationController.transcriptionFailedMessage,
    );

    failing = false;
    await controller.startListening();
    expect(controller.errorMessage, isNull);
    await controller.stopListening();

    expect(controller.errorMessage, isNull);
    expect(controller.latestTranscript, 'Back to normal.');
  });

  test('a transcription timeout surfaces its reason as the error', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: HangingSttEngine(),
      audioRecorder: FakeAudioRecorder(),
      transcribeTimeout: const Duration(milliseconds: 50),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.errorMessage, contains('took too long'));
  });

  test('silent audio is not reported as an error', () async {
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: FakeSttEngine(transcript: '   '),
      audioRecorder: FakeAudioRecorder(),
    );

    await controller.startListening();
    await controller.stopListening();

    expect(controller.errorMessage, isNull);
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
      DictationController.insertionFailedMessage,
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

class HangingSttEngine implements SttEngine {
  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) =>
      Completer<String>().future;
}

class SwitchableSttEngine implements SttEngine {
  SwitchableSttEngine(this._transcribe);

  final Future<String> Function(AudioRecording) _transcribe;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(AudioRecording recording) => _transcribe(recording);
}

class HangingStopAudioRecorder implements AudioRecorder {
  @override
  Future<void> start() async {}

  @override
  Future<AudioRecording> stop() => Completer<AudioRecording>().future;
}

/// Overlay calls that throw must never strand the dictation phase.
class FailingOverlayPlatformBridge extends MockPlatformBridge {
  FailingOverlayPlatformBridge({this.failTranscribingOnly = false});

  final bool failTranscribingOnly;

  @override
  Future<void> showTranscribingOverlay() async {
    throw StateError('overlay unavailable');
  }

  @override
  Future<void> hideListeningOverlay() async {
    if (failTranscribingOnly) {
      return super.hideListeningOverlay();
    }
    throw StateError('overlay unavailable');
  }

  @override
  Future<void> showDictationFailureNotification(String message) async {
    if (failTranscribingOnly) {
      return super.showDictationFailureNotification(message);
    }
    throw StateError('notifier unavailable');
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
  Future<void> showDictationFailureNotification(String message) async {}

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    insertAttempted = true;
    throw StateError('focused field unavailable');
  }

  @override
  Future<void> ensureLaunchAtStartup() async {}
}
