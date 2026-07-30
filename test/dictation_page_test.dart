import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/mock_audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';
import 'package:typemate/src/features/dictation/dictation_page.dart';

class FixedTranscriptSttEngine implements SttEngine {
  FixedTranscriptSttEngine(this.transcript);

  final String transcript;
  bool prepared = false;

  @override
  Future<bool> isReady() async => prepared;

  @override
  Future<void> prepare() async {
    prepared = true;
  }

  @override
  Future<String> transcribe(AudioRecording recording) async => transcript;
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('hold to talk produces and copies a transcript', (tester) async {
    final bridge = MockPlatformBridge();
    final engine = FixedTranscriptSttEngine('ship the android build');
    final controller = DictationController(
      platformBridge: bridge,
      sttEngine: engine,
      audioRecorder: MockAudioRecorder(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(DictationPage(controller: controller)));
    await tester.pump();

    final button = find.byKey(const Key('hold-to-dictate-button'));
    expect(button, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.phase.name, 'listening');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('ship the android build'), findsOneWidget);
    expect(
      bridge.lastInsertedText,
      'ship the android build',
      reason: 'The bridge insertion is what lands the text on the clipboard.',
    );
  });

  testWidgets('fresh install walks through the model download', (tester) async {
    final directory = Directory.systemTemp.createTempSync('typemate-dict');
    addTearDown(() => directory.deleteSync(recursive: true));
    final provisioner = SttModelProvisioner(
      modelDirectory: directory,
      files: const [
        SttModelFile(
          url: 'https://example.test/a',
          relativePath: 'a.onnx',
          expectedBytes: 10,
        ),
      ],
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            target.writeAsStringSync('0123456789');
            onProgress(10);
          },
    );
    addTearDown(provisioner.dispose);
    final engine = FixedTranscriptSttEngine('hello');
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: engine,
      audioRecorder: MockAudioRecorder(),
    );
    addTearDown(controller.dispose);

    var permissionWarmUps = 0;
    await tester.pumpWidget(
      wrap(
        DictationPage(
          controller: controller,
          modelProvisioner: provisioner,
          microphonePermissionWarmUp: () async => permissionWarmUps += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start-model-download')), findsOneWidget);
    expect(
      find.byKey(const Key('hold-to-dictate-button')),
      findsNothing,
      reason: 'No dictation surface before the model exists.',
    );
    expect(
      engine.prepared,
      isFalse,
      reason: 'The engine must not try to load missing model files.',
    );
    expect(
      permissionWarmUps,
      0,
      reason: 'No permission prompt while dictation is still impossible.',
    );

    await tester.tap(find.byKey(const Key('start-model-download')));
    await tester.pumpAndSettle();

    expect(provisioner.isReady, isTrue);
    expect(find.byKey(const Key('hold-to-dictate-button')), findsOneWidget);
    expect(
      engine.prepared,
      isTrue,
      reason: 'The engine warms up as soon as the model lands.',
    );
    expect(
      permissionWarmUps,
      1,
      reason: 'The permission prompt fires once dictation becomes possible.',
    );
  });

  testWidgets('an already provisioned model goes straight to dictation', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('typemate-dict2');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/a.onnx').writeAsStringSync('0123456789');
    final provisioner = SttModelProvisioner(
      modelDirectory: directory,
      files: const [
        SttModelFile(
          url: 'https://example.test/a',
          relativePath: 'a.onnx',
          expectedBytes: 10,
        ),
      ],
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            fail('Nothing to download when the model already exists.');
          },
    );
    addTearDown(provisioner.dispose);
    final engine = FixedTranscriptSttEngine('hello');
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: engine,
      audioRecorder: MockAudioRecorder(),
    );
    addTearDown(controller.dispose);

    var permissionWarmUps = 0;
    await tester.pumpWidget(
      wrap(
        DictationPage(
          controller: controller,
          modelProvisioner: provisioner,
          microphonePermissionWarmUp: () async => permissionWarmUps += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hold-to-dictate-button')), findsOneWidget);
    expect(engine.prepared, isTrue);
    expect(
      permissionWarmUps,
      1,
      reason: 'A provisioned install prompts for the microphone right away.',
    );
  });
}
