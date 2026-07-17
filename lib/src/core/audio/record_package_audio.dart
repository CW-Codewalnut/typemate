import 'dart:async';
import 'dart:io';

import 'package:record/record.dart' as record_pkg;

import 'audio_recorder.dart';
import 'ffmpeg_audio_recorder.dart' show Clock;
import 'microphone_discovery.dart';
import 'microphone_audio_recorder_factory.dart' show AudioRecorderFactory;

/// Thin seam over the record plugin so adapters stay unit-testable; the
/// plugin's channel-backed recorder cannot be faked directly.
abstract interface class RecordBackend {
  Future<List<record_pkg.InputDevice>> listInputDevices();

  Future<void> start(record_pkg.RecordConfig config, {required String path});

  Future<String?> stop();

  Future<void> dispose();
}

class PluginRecordBackend implements RecordBackend {
  PluginRecordBackend() : _recorder = record_pkg.AudioRecorder();

  final record_pkg.AudioRecorder _recorder;

  @override
  Future<List<record_pkg.InputDevice>> listInputDevices() =>
      _recorder.listInputDevices();

  @override
  Future<void> start(record_pkg.RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// Windows microphone discovery through the record plugin's
/// MediaFoundation backend — no external binaries involved.
///
/// The device label becomes [MicrophoneDevice.name] and the plugin device
/// id becomes [MicrophoneDevice.alternativeName], which the recorder needs
/// to select the same device.
class RecordPackageMicrophoneDiscovery implements MicrophoneDiscovery {
  RecordPackageMicrophoneDiscovery({RecordBackend Function()? backendFactory})
    : _backendFactory = backendFactory ?? PluginRecordBackend.new;

  final RecordBackend Function() _backendFactory;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    final backend = _backendFactory();
    try {
      final devices = await backend.listInputDevices();
      return [
        for (final device in devices)
          MicrophoneDevice(name: device.label, alternativeName: device.id),
      ];
    } finally {
      await backend.dispose();
    }
  }
}

class RecordPackageAudioRecorderFactory implements AudioRecorderFactory {
  RecordPackageAudioRecorderFactory({
    required this.outputDirectory,
    this.backendFactory,
    this.clock,
  });

  final Directory outputDirectory;
  final RecordBackend Function()? backendFactory;
  final Clock? clock;

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    return RecordPackageAudioRecorder(
      microphone: microphone,
      outputDirectory: outputDirectory,
      backendFactory: backendFactory,
      clock: clock,
    );
  }
}

/// Records 16 kHz mono 16-bit WAV through the record plugin, matching the
/// format whisper and Parakeet expect.
class RecordPackageAudioRecorder implements AudioRecorder {
  RecordPackageAudioRecorder({
    required this._microphone,
    required this._outputDirectory,
    RecordBackend Function()? backendFactory,
    Clock? clock,
  }) : _backendFactory = backendFactory ?? PluginRecordBackend.new,
       _clock = clock ?? DateTime.now;

  final MicrophoneDevice _microphone;
  final Directory _outputDirectory;
  final RecordBackend Function() _backendFactory;
  final Clock _clock;

  RecordBackend? _backend;
  DateTime? _startedAt;
  String? _outputPath;

  @override
  Future<void> start() async {
    if (_backend != null) {
      return;
    }
    await _outputDirectory.create(recursive: true);
    _startedAt = _clock();
    _outputPath =
        '${_outputDirectory.path}/typemate-${_timestamp(_startedAt!)}.wav';

    final backend = _backendFactory();
    _backend = backend;
    await backend.start(
      record_pkg.RecordConfig(
        encoder: record_pkg.AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        device: record_pkg.InputDevice(
          id: _microphone.alternativeName ?? _microphone.name,
          label: _microphone.name,
        ),
      ),
      path: _outputPath!,
    );
  }

  @override
  Future<AudioRecording> stop() async {
    final backend = _backend;
    final startedAt = _startedAt;
    final outputPath = _outputPath;
    if (backend == null || startedAt == null || outputPath == null) {
      return const AudioRecording(path: '', duration: Duration.zero);
    }

    final recordedPath = await backend.stop();
    await backend.dispose();
    _backend = null;
    _startedAt = null;
    _outputPath = null;

    return AudioRecording(
      path: recordedPath ?? outputPath,
      duration: _clock().difference(startedAt),
    );
  }

  static String _timestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');

    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
