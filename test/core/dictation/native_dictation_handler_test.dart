import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/microphone_audio_recorder_factory.dart'
    show AudioRecorderFactory;
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/platform/android/native_dictation_channel.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';

class _FakeRecorder implements AudioRecorder {
  _FakeRecorder(this.recording, {this.failStart = false});

  final AudioRecording recording;
  final bool failStart;
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start() async {
    if (failStart) {
      throw StateError('Microphone permission was not granted.');
    }
    started = true;
  }

  @override
  Future<AudioRecording> stop() async {
    stopped = true;
    return recording;
  }
}

class _FakeRecorderFactory implements AudioRecorderFactory {
  _FakeRecorderFactory(this.recorder);

  final _FakeRecorder recorder;

  @override
  AudioRecorder create(MicrophoneDevice microphone) => recorder;
}

class _FakeEngine implements DisposableSttEngine {
  _FakeEngine(this.transcript, {this.fail = false});

  final String transcript;
  final bool fail;
  bool prepared = false;
  bool shutDown = false;

  @override
  Future<bool> isReady() async => prepared;

  @override
  Future<void> prepare() async {
    prepared = true;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    if (fail) {
      throw StateError('decode failed');
    }
    return transcript;
  }

  @override
  Future<void> shutdown() async {
    shutDown = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('typemate-ime');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  File recordingFile() =>
      File('${directory.path}/clip.wav')..writeAsStringSync('fake-audio');

  AudioRecording recordingFor(File file) =>
      AudioRecording(path: file.path, duration: const Duration(seconds: 2));

  test('start then stop transcribes and deletes the recording', () async {
    final file = recordingFile();
    final recorder = _FakeRecorder(recordingFor(file));
    final engine = _FakeEngine('deploy on friday');
    final handler = NativeDictationHandler(
      engine: engine,
      recorderFactory: _FakeRecorderFactory(recorder),
    );

    await handler.start();
    expect(recorder.started, isTrue);

    final transcript = await handler.stop();

    expect(transcript, 'deploy on friday');
    expect(
      file.existsSync(),
      isFalse,
      reason: 'Dictation audio is transcribe-and-delete.',
    );
  });

  test('a successful dictation lands in history; silence does not', () async {
    final calls = <(String, Duration)>[];
    Future<void> record(
      String transcript, {
      required Duration duration,
    }) async => calls.add((transcript, duration));

    final speaking = NativeDictationHandler(
      engine: _FakeEngine('note this down'),
      recorderFactory: _FakeRecorderFactory(
        _FakeRecorder(recordingFor(recordingFile())),
      ),
      onTranscriptGenerated: record,
    );
    await speaking.start();
    await speaking.stop();
    expect(calls, [('note this down', const Duration(seconds: 2))]);

    final silent = NativeDictationHandler(
      engine: _FakeEngine('[BLANK_AUDIO]'),
      recorderFactory: _FakeRecorderFactory(
        _FakeRecorder(recordingFor(recordingFile())),
      ),
      onTranscriptGenerated: record,
    );
    await silent.start();
    await silent.stop();
    expect(calls, hasLength(1), reason: 'Silence writes no history entry.');
  });

  test('a line break never reaches the focused field', () async {
    // This is the surface the floating mic and the physical-keyboard
    // shortcut use, and it inserts straight into whatever app is focused.
    // A newline is not text there: chat boxes, search fields and address
    // bars read it as SEND, so a transcript carrying one fires the message
    // off mid-sentence. Trimming alone leaves interior breaks, which is
    // exactly the case that bites.
    final calls = <String>[];
    final handler = NativeDictationHandler(
      engine: _FakeEngine('  ship it\nby friday\r\nplease  '),
      recorderFactory: _FakeRecorderFactory(
        _FakeRecorder(recordingFor(recordingFile())),
      ),
      onTranscriptGenerated: (transcript, {required duration}) async =>
          calls.add(transcript),
    );

    await handler.start();
    final transcript = await handler.stop();

    expect(transcript, 'ship it by friday please');
    expect(calls, [
      'ship it by friday please',
    ], reason: 'History stores what was typed, not the raw engine output.');
  });

  test('silence comes back as an empty transcript', () async {
    final recorder = _FakeRecorder(recordingFor(recordingFile()));
    final handler = NativeDictationHandler(
      engine: _FakeEngine('[BLANK_AUDIO]'),
      recorderFactory: _FakeRecorderFactory(recorder),
    );

    await handler.start();

    expect(await handler.stop(), isEmpty);
  });

  test(
    'stop without start returns empty without touching the engine',
    () async {
      final handler = NativeDictationHandler(
        engine: _FakeEngine('never used'),
        recorderFactory: _FakeRecorderFactory(
          _FakeRecorder(recordingFor(recordingFile())),
        ),
      );

      expect(await handler.stop(), isEmpty);
    },
  );

  test(
    'a missing model refuses to start with the model-missing code',
    () async {
      final provisioner = SttModelProvisioner(
        modelDirectory: Directory('${directory.path}/models'),
        files: const [
          SttModelFile(
            url: 'https://example.test/a',
            relativePath: 'a.onnx',
            expectedBytes: 10,
          ),
        ],
        hasActiveDownload: () async => false,
      );
      addTearDown(provisioner.dispose);
      final handler = NativeDictationHandler(
        engine: _FakeEngine('unused'),
        recorderFactory: _FakeRecorderFactory(
          _FakeRecorder(recordingFor(recordingFile())),
        ),
        provisioner: provisioner,
      );

      await expectLater(
        handler.start(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            NativeDictationErrorCodes.modelMissing,
          ),
        ),
      );
    },
  );

  test('a recorder failure maps to the record-failed code', () async {
    final handler = NativeDictationHandler(
      engine: _FakeEngine('unused'),
      recorderFactory: _FakeRecorderFactory(
        _FakeRecorder(recordingFor(recordingFile()), failStart: true),
      ),
    );

    await expectLater(
      handler.start(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          NativeDictationErrorCodes.recordFailed,
        ),
      ),
    );
  });

  test('a transcription failure maps to transcribe-failed and still '
      'deletes the audio', () async {
    final file = recordingFile();
    final handler = NativeDictationHandler(
      engine: _FakeEngine('unused', fail: true),
      recorderFactory: _FakeRecorderFactory(_FakeRecorder(recordingFor(file))),
    );

    await handler.start();
    await expectLater(
      handler.stop(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          NativeDictationErrorCodes.transcribeFailed,
        ),
      ),
    );
    expect(file.existsSync(), isFalse);
  });

  test('cancel discards the recording without transcribing', () async {
    final file = recordingFile();
    final engine = _FakeEngine('should not run');
    final recorder = _FakeRecorder(recordingFor(file));
    final handler = NativeDictationHandler(
      engine: engine,
      recorderFactory: _FakeRecorderFactory(recorder),
    );

    await handler.start();
    await handler.cancel();

    expect(recorder.stopped, isTrue);
    expect(file.existsSync(), isFalse);
  });

  test('warmUp prepares the engine only when the model is present', () async {
    final engine = _FakeEngine('unused');
    final provisioner = SttModelProvisioner(
      modelDirectory: directory,
      files: const [
        SttModelFile(
          url: 'https://example.test/a',
          relativePath: 'a.onnx',
          expectedBytes: 10,
        ),
      ],
      hasActiveDownload: () async => false,
    );
    addTearDown(provisioner.dispose);
    final handler = NativeDictationHandler(
      engine: engine,
      recorderFactory: _FakeRecorderFactory(
        _FakeRecorder(recordingFor(recordingFile())),
      ),
      provisioner: provisioner,
    );

    await handler.warmUp();
    expect(engine.prepared, isFalse, reason: 'No model, no load.');

    File('${directory.path}/a.onnx').writeAsStringSync('0123456789');
    await handler.warmUp();
    expect(engine.prepared, isTrue);
  });

  test('shutdown cancels any dictation and frees the engine', () async {
    final file = recordingFile();
    final engine = _FakeEngine('unused');
    final handler = NativeDictationHandler(
      engine: engine,
      recorderFactory: _FakeRecorderFactory(_FakeRecorder(recordingFor(file))),
    );

    await handler.start();
    await handler.shutdown();

    expect(engine.shutDown, isTrue);
    expect(file.existsSync(), isFalse);
  });
}
