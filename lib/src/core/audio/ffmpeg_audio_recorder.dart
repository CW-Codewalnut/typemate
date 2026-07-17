import 'dart:async';
import 'dart:io';

import 'audio_recorder.dart';

typedef Clock = DateTime Function();

abstract interface class RecorderProcessRunner {
  Future<RecorderProcess> start(String executable, List<String> arguments);
}

abstract interface class RecorderProcess {
  void requestStop();

  Future<int> get exitCode;
}

class FfmpegAudioRecorder implements AudioRecorder {
  /// Captures from a PulseAudio source (also served by PipeWire's Pulse
  /// compatibility layer, the default on modern desktops and WSLg).
  FfmpegAudioRecorder.linux({
    required String deviceName,
    required Directory outputDirectory,
    String executable = 'ffmpeg',
    RecorderProcessRunner? processRunner,
    Clock? clock,
  }) : this._(
         inputArguments: ['-f', 'pulse', '-i', deviceName],
         outputDirectory: outputDirectory,
         executable: executable,
         processRunner: processRunner ?? const DartRecorderProcessRunner(),
         clock: clock ?? DateTime.now,
       );

  FfmpegAudioRecorder._({
    required this._inputArguments,
    required this._outputDirectory,
    required this._executable,
    required this._processRunner,
    required this._clock,
  });

  final List<String> _inputArguments;
  final Directory _outputDirectory;
  final String _executable;
  final RecorderProcessRunner _processRunner;
  final Clock _clock;

  RecorderProcess? _process;
  DateTime? _startedAt;
  File? _outputFile;

  @override
  Future<void> start() async {
    if (_process != null) {
      return;
    }

    await _outputDirectory.create(recursive: true);
    _startedAt = _clock();
    _outputFile = File(
      '${_outputDirectory.path}/typemate-${_timestamp(_startedAt!)}.wav',
    );

    final arguments = [
      '-y',
      ..._inputArguments,
      '-ac',
      '1',
      '-ar',
      '16000',
      '-sample_fmt',
      's16',
      _outputFile!.path,
    ];

    _process = await _processRunner.start(_executable, arguments);
  }

  @override
  Future<AudioRecording> stop() async {
    final process = _process;
    final outputFile = _outputFile;
    final startedAt = _startedAt;

    if (process == null || outputFile == null || startedAt == null) {
      return const AudioRecording(path: '', duration: Duration.zero);
    }

    process.requestStop();
    await process.exitCode;

    _process = null;
    _outputFile = null;
    _startedAt = null;

    return AudioRecording(
      path: outputFile.path,
      duration: _clock().difference(startedAt),
    );
  }

  static String _timestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');

    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

class DartRecorderProcessRunner implements RecorderProcessRunner {
  const DartRecorderProcessRunner();

  @override
  Future<RecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.normal,
    );
    return DartRecorderProcess(process);
  }
}

class DartRecorderProcess implements RecorderProcess {
  DartRecorderProcess(this._process) {
    unawaited(_process.stdout.drain<void>());
    unawaited(_process.stderr.drain<void>());
  }

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void requestStop() {
    _process.stdin.writeln('q');
    unawaited(_process.stdin.close());
  }
}
