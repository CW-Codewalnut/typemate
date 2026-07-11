import 'dart:io';

import '../audio/audio_recorder.dart';
import 'stt_engine.dart';

class SttProcessResult {
  const SttProcessResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

abstract interface class SttProcessRunner {
  Future<SttProcessResult> run(String executable, List<String> arguments);
}

class WhisperCliSttEngine implements SttEngine {
  WhisperCliSttEngine({
    required this.executable,
    required this.modelPath,
    SttProcessRunner? processRunner,
  }) : processRunner = processRunner ?? const DartSttProcessRunner();

  final String executable;
  final String modelPath;
  final SttProcessRunner processRunner;

  @override
  Future<bool> isReady() async {
    try {
      final result = await processRunner.run(executable, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> prepare() async {
    if (!await isReady()) {
      throw const SttRuntimeException(
        'Local speech runtime is not ready. Check whisper.cpp and the model file.',
      );
    }
  }

  @override
  Future<String> transcribe(AudioRecording recording) async {
    final result = await processRunner.run(executable, [
      '-m',
      modelPath,
      '-f',
      recording.path,
      '--no-timestamps',
    ]);

    if (result.exitCode != 0) {
      throw const SttRuntimeException(
        'Local transcription failed. Check the whisper.cpp runtime and model file.',
      );
    }

    return _parseTranscript(result.output);
  }

  String _parseTranscript(String output) {
    return output
        .split('\n')
        .map(_stripTimestampPrefix)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripTimestampPrefix(String line) {
    return line.replaceFirst(RegExp(r'^\[[0-9:.]+\s+-->\s+[0-9:.]+\]\s*'), '');
  }
}

class SttRuntimeException implements Exception {
  const SttRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DartSttProcessRunner implements SttProcessRunner {
  const DartSttProcessRunner();

  @override
  Future<SttProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return SttProcessResult(
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}',
    );
  }
}
