import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/audio/mock_audio_recorder.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/platform/mock_platform_bridge.dart';
import 'package:typemate/src/core/stt/stt_engine.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';
import 'package:typemate/src/features/dictate/components/dictation_card.dart';

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
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  SttModelProvisioner provisionerFor(
    Directory directory, {
    bool downloadable = true,
  }) => SttModelProvisioner(
    modelDirectory: directory,
    files: const [
      SttModelFile(
        url: 'https://example.test/a',
        relativePath: 'a.onnx',
        expectedBytes: 10,
      ),
    ],
    downloader:
        (file, target, {required resumeFromBytes, required onProgress}) async {
          if (!downloadable) {
            fail('Nothing to download when the model already exists.');
          }
          target.writeAsStringSync('0123456789');
          onProgress(10);
        },
  );

  testWidgets('the mic button dictates and inserts via the bridge', (
    tester,
  ) async {
    final bridge = MockPlatformBridge();
    final controller = DictationController(
      platformBridge: bridge,
      sttEngine: FixedTranscriptSttEngine('ship the android build'),
      audioRecorder: MockAudioRecorder(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(HoldToTalkMicButton(controller: controller)));
    await tester.pump();

    final button = find.byKey(const Key('hold-to-dictate-button'));
    expect(button, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.phase.name, 'listening');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(bridge.lastInsertedText, 'ship the android build');
  });

  testWidgets('fresh install walks through the model download', (tester) async {
    final directory = Directory.systemTemp.createTempSync('typemate-card');
    addTearDown(() => directory.deleteSync(recursive: true));
    final provisioner = provisionerFor(directory);
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
        DictationCard(
          controller: controller,
          modelProvisioner: provisioner,
          microphonePermissionWarmUp: () async => permissionWarmUps += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start-model-download')), findsOneWidget);
    expect(engine.prepared, isFalse);
    expect(permissionWarmUps, 0);

    await tester.tap(find.byKey(const Key('start-model-download')));
    await tester.pumpAndSettle();

    expect(provisioner.isReady, isTrue);
    expect(find.byKey(const Key('start-model-download')), findsNothing);
    expect(
      engine.prepared,
      isFalse,
      reason: 'Engine loads lazily on first dictation, not on model ready.',
    );
    expect(permissionWarmUps, 1);
  });

  testWidgets('a provisioned model needs no download interaction', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('typemate-card2');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/a.onnx').writeAsStringSync('0123456789');
    final provisioner = provisionerFor(directory, downloadable: false);
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
        DictationCard(
          controller: controller,
          modelProvisioner: provisioner,
          microphonePermissionWarmUp: () async => permissionWarmUps += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start-model-download')), findsNothing);
    expect(
      engine.prepared,
      isFalse,
      reason: 'Engine loads lazily on first dictation, not on model ready.',
    );
    expect(permissionWarmUps, 1);
  });

  testWidgets(
    'desktop slim install offers the download, then warms the engine',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('typemate-desk');
      addTearDown(() => directory.deleteSync(recursive: true));
      final provisioner = provisionerFor(directory);
      addTearDown(provisioner.dispose);
      final engine = FixedTranscriptSttEngine('hello');
      final controller = DictationController(
        platformBridge: MockPlatformBridge(),
        sttEngine: engine,
        audioRecorder: MockAudioRecorder(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          DictationCard(
            controller: controller,
            desktop: true,
            modelProvisioner: provisioner,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('start-model-download')), findsOneWidget);
      expect(find.textContaining('on this computer'), findsOneWidget);
      expect(engine.prepared, isFalse);

      await tester.tap(find.byKey(const Key('start-model-download')));
      await tester.pumpAndSettle();

      expect(provisioner.isReady, isTrue);
      expect(find.byKey(const Key('start-model-download')), findsNothing);
      expect(
        engine.prepared,
        isTrue,
        reason: 'Desktop keeps the selected model warm once it exists.',
      );
    },
  );

  testWidgets('desktop with nothing to download warms the engine immediately', (
    tester,
  ) async {
    final engine = FixedTranscriptSttEngine('hello');
    final controller = DictationController(
      platformBridge: MockPlatformBridge(),
      sttEngine: engine,
      audioRecorder: MockAudioRecorder(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(DictationCard(controller: controller, desktop: true)),
    );
    await tester.pumpAndSettle();

    expect(
      engine.prepared,
      isTrue,
      reason: 'Desktop prepares eagerly even with nothing to download.',
    );
  });
}
