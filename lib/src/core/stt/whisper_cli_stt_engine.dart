import 'dart:convert';
import 'dart:io';

import '../../models/speech_language_options.dart';
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
    final languageCode = _normalizedLanguageCode();
    final outputFilePrefix = _transcriptOutputFilePrefix();
    final result = await processRunner.run(executable, [
      '-m',
      modelPath,
      '-f',
      recording.path,
      '--no-timestamps',
      // Greedy decoding keeps push-to-talk latency low; whisper-cli's default
      // 5-beam search is several times slower on large models.
      '--beam-size',
      '1',
      '--best-of',
      '1',
      ..._audioContextArguments(recording.duration, languageCode),
      '-otxt',
      '-of',
      outputFilePrefix,
      '-l',
      languageCode,
      ..._promptArgumentsForLanguage(languageCode),
    ]);

    if (result.exitCode != 0) {
      throw const SttRuntimeException(
        'Local transcription failed. Check the whisper.cpp runtime and model file.',
      );
    }

    return _parseTranscript(await _transcriptOutput(outputFilePrefix, result));
  }

  String _transcriptOutputFilePrefix() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${Directory.systemTemp.path}/typemate-whisper-$now';
  }

  Future<String> _transcriptOutput(
    String outputFilePrefix,
    SttProcessResult result,
  ) async {
    final outputFile = File('$outputFilePrefix.txt');
    if (!await outputFile.exists()) {
      return result.output;
    }

    try {
      return await outputFile.readAsString(encoding: utf8);
    } finally {
      await outputFile.delete().catchError((_) => outputFile);
    }
  }

  // Whisper always encodes a 30s window (1500 frames), so encoding cost is
  // fixed no matter how short the clip is. Shrinking the window to the clip
  // length (plus margin) cuts CPU latency several-fold for short dictation.
  // Language auto-detection misfires on a reduced window and produces garbage
  // transcripts, so the speedup only applies to an explicit language.
  static const _fullAudioContextFrames = 1500;
  static const _minimumAudioContextFrames = 128;
  static const _audioContextMarginSeconds = 2.0;

  List<String> _audioContextArguments(Duration duration, String languageCode) {
    if (languageCode == 'auto' || duration <= Duration.zero) {
      return const [];
    }
    final paddedSeconds =
        duration.inMilliseconds / 1000 + _audioContextMarginSeconds;
    if (paddedSeconds >= 30) {
      return const [];
    }
    final frames = (paddedSeconds / 30 * _fullAudioContextFrames).ceil();
    final context = frames < _minimumAudioContextFrames
        ? _minimumAudioContextFrames
        : frames;
    return ['--audio-ctx', '$context'];
  }

  String _normalizedLanguageCode() {
    final code = languageCodeProvider().trim().toLowerCase();
    return code.isEmpty ? 'auto' : code;
  }

  List<String> _promptArgumentsForLanguage(String languageCode) {
    if (languageCode == 'auto') {
      return const [];
    }
    final languageLabel = speechLanguageLabelForCode(languageCode);
    if (languageLabel == null) {
      return const [];
    }
    final prompt =
        _transcriptionPromptByLanguage[languageCode] ??
        'Transcribe the spoken $languageLabel audio in $languageLabel. '
            'Use the normal writing system for $languageLabel. '
            'Do not translate into English or any other language.';
    return ['--prompt', prompt];
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

const Map<String, String> _transcriptionPromptByLanguage = {
  'hi':
      'हिंदी भाषण को देवनागरी लिपि में ठीक-ठीक लिखें। अंग्रेज़ी में अनुवाद न करें।',
};

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
