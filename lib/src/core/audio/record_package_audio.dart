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

  /// Whether audio capture is allowed. On Android this also shows the
  /// runtime permission dialog when it has not been answered yet; desktop
  /// platforms report true (Windows/Linux) or the OS consent state (macOS).
  Future<bool> hasPermission();

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
  Future<bool> hasPermission() => _recorder.hasPermission();

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

/// Triggers the OS microphone permission prompt (Android) ahead of the
/// first dictation, so the first hold-to-talk is not interrupted by the
/// permission dialog appearing mid-recording. Best-effort: a denial here
/// still surfaces properly on the next recording attempt.
Future<void> warmUpMicrophonePermission({
  RecordBackend Function()? backendFactory,
}) async {
  final backend = (backendFactory ?? PluginRecordBackend.new)();
  try {
    await backend.hasPermission();
  } catch (_) {
    // Warm-up only; the recorder reports real failures.
  } finally {
    await backend.dispose();
  }
}

class RecordPackageAudioRecorderFactory implements AudioRecorderFactory {
  RecordPackageAudioRecorderFactory({
    required this.outputDirectory,
    this.backendFactory,
    this.clock,
    this.useSystemDefaultDevice = false,
    this.requestPermission = false,
  });

  final Directory outputDirectory;
  final RecordBackend Function()? backendFactory;
  final Clock? clock;

  /// Record from the OS-selected input instead of an explicit device id
  /// (Android: the plugin expects no device there).
  final bool useSystemDefaultDevice;

  /// Ask for the microphone permission before capturing (Android runtime
  /// permission). Desktop keeps its existing behavior of failing at start.
  final bool requestPermission;

  @override
  AudioRecorder create(MicrophoneDevice microphone) {
    return RecordPackageAudioRecorder(
      microphone: microphone,
      outputDirectory: outputDirectory,
      backendFactory: backendFactory,
      clock: clock,
      useSystemDefaultDevice: useSystemDefaultDevice,
      requestPermission: requestPermission,
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
    this._useSystemDefaultDevice = false,
    this._requestPermission = false,
  }) : _backendFactory = backendFactory ?? PluginRecordBackend.new,
       _clock = clock ?? DateTime.now;

  final MicrophoneDevice _microphone;
  final Directory _outputDirectory;
  final RecordBackend Function() _backendFactory;
  final Clock _clock;
  final bool _useSystemDefaultDevice;
  final bool _requestPermission;

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
    if (_requestPermission && !await backend.hasPermission()) {
      _backend = null;
      _startedAt = null;
      _outputPath = null;
      await backend.dispose();
      throw StateError('Microphone permission was not granted.');
    }
    await backend.start(
      record_pkg.RecordConfig(
        encoder: record_pkg.AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        // The system default input carries no device id; the OS routes it
        // to the active microphone (Android).
        device: _useSystemDefaultDevice
            ? null
            : record_pkg.InputDevice(
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

    // Milliseconds included: at second resolution two recordings started
    // in the same second write to one path, and the second one silently
    // overwrites the first. Normally unreachable, but a start/stop race
    // can reach it.
    String three(int number) => number.toString().padLeft(3, '0');

    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}'
        '-${three(value.millisecond)}';
  }
}
