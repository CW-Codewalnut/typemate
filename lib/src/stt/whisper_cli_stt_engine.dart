import 'dart:convert';
import 'dart:io';

import '../audio/audio_recorder.dart';
import 'stt_engine.dart';

class SttProcessResult {
  const SttProcessResult({
    required this.exitCode,
    required this.output,
    this.diagnostics = '',
  });

  final int exitCode;
  final String output;
  final String diagnostics;
}

abstract interface class SttProcessRunner {
  Future<SttProcessResult> run(String executable, List<String> arguments);
}

typedef SttLanguageCodeProvider = String Function();

class WhisperCliSttEngine implements SttEngine {
  WhisperCliSttEngine({
    required this.executable,
    required this.modelPath,
    SttProcessRunner? processRunner,
    SttLanguageCodeProvider? languageCodeProvider,
  }) : processRunner = processRunner ?? const DartSttProcessRunner(),
       languageCodeProvider = languageCodeProvider ?? (() => 'auto');

  final String executable;
  final String modelPath;
  final SttProcessRunner processRunner;
  final SttLanguageCodeProvider languageCodeProvider;

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
      '-l',
      _normalizedLanguageCode(),
    ]);

    if (result.exitCode != 0) {
      throw const SttRuntimeException(
        'Local transcription failed. Check the whisper.cpp runtime and model file.',
      );
    }

    return _parseTranscript(result.output);
  }

  String _normalizedLanguageCode() {
    final code = languageCodeProvider().trim().toLowerCase();
    return code.isEmpty ? 'auto' : code;
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
    final result = await Process.run(
      executable,
      arguments,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return SttProcessResult(
      exitCode: result.exitCode,
      output: '${result.stdout}',
      diagnostics: '${result.stderr}',
    );
  }
}
