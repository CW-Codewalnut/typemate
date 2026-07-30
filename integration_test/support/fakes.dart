import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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

/// Recorder that leaves a real 16-bit PCM WAV on disk, for tests that run a
/// real STT engine (which parses the recording) instead of a fake one.
class WavWritingAudioRecorder implements AudioRecorder {
  WavWritingAudioRecorder({required this.outputDirectory});

  final Directory outputDirectory;
  bool isRecording = false;
  int _counter = 0;

  @override
  Future<void> start() async {
    isRecording = true;
  }

  @override
  Future<AudioRecording> stop() async {
    isRecording = false;
    _counter += 1;
    final file = File('${outputDirectory.path}/e2e-recording-$_counter.wav');
    await file.writeAsBytes(
      buildPcm16Wav(sampleRate: 16000, samples: [100, -100, 200, -200]),
    );
    return AudioRecording(
      path: file.path,
      duration: const Duration(milliseconds: 1200),
    );
  }
}

class WavWritingAudioRecorderFactory implements AudioRecorderFactory {
  WavWritingAudioRecorderFactory({required this.outputDirectory});

  final Directory outputDirectory;
  final List<WavWritingAudioRecorder> createdRecorders = [];

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    final recorder = WavWritingAudioRecorder(outputDirectory: outputDirectory);
    createdRecorders.add(recorder);
    return recorder;
  }
}

/// Minimal valid RIFF/WAVE file: 44-byte header plus 16-bit PCM samples.
Uint8List buildPcm16Wav({required int sampleRate, required List<int> samples}) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  void writeAscii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
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

/// Pumps until [condition] holds (bounded). The mobile shell does work
/// off the frame pipeline (platform-channel permission warm-up before
/// engine prepare), so waiting on frames alone races real devices.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
