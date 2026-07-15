import 'dart:io';

import 'package:typemate/src/core/audio/audio_recorder.dart';
import 'package:typemate/src/core/stt/whisper_cli_stt_engine.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printUsage();
    return;
  }

  final options = _BenchmarkOptions.fromArguments(
    arguments,
    Platform.environment,
  );
  if (options == null) {
    _printUsage(to: stderr);
    exitCode = 64;
    return;
  }

  final executable = File(options.executable);
  if (!executable.existsSync() && !await _canRunFromPath(options.executable)) {
    stderr.writeln('whisper_cli_missing=${options.executable}');
    exitCode = 66;
    return;
  }

  final model = File(options.modelPath);
  if (!model.existsSync()) {
    stderr.writeln('model_missing=${model.absolute.path}');
    exitCode = 66;
    return;
  }

  final audio = File(options.audioPath);
  if (!audio.existsSync()) {
    stderr.writeln('audio_missing=${audio.absolute.path}');
    exitCode = 66;
    return;
  }

  final engine = WhisperCliSttEngine(
    executable: options.executable,
    modelPath: options.modelPath,
  );

  final stopwatch = Stopwatch()..start();
  try {
    await engine.prepare();
    final transcript = await engine.transcribe(
      AudioRecording(path: options.audioPath, duration: Duration.zero),
    );
    stopwatch.stop();

    stdout.writeln('runtime=${options.executable}');
    stdout.writeln('model=${model.absolute.path}');
    stdout.writeln('audio=${audio.absolute.path}');
    stdout.writeln('elapsed_ms=${stopwatch.elapsedMilliseconds}');
    stdout.writeln('transcript=$transcript');
  } on SttRuntimeException catch (error) {
    stderr.writeln('stt_error=${error.message}');
    exitCode = 1;
  }
}

Future<bool> _canRunFromPath(String executable) async {
  try {
    final result = await Process.run(executable, ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void _printUsage({IOSink? to}) {
  final sink = to ?? stdout;
  sink.writeln(
    'Usage: dart run tool/benchmark_whisper_cli.dart --audio <sample.wav> [--cli <whisper-cli>] [--model <model.bin>]',
  );
  sink.writeln('Env fallback: TYPEMATE_WHISPER_CLI and TYPEMATE_WHISPER_MODEL');
}

class _BenchmarkOptions {
  const _BenchmarkOptions({
    required this.executable,
    required this.modelPath,
    required this.audioPath,
  });

  final String executable;
  final String modelPath;
  final String audioPath;

  static _BenchmarkOptions? fromArguments(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    final cli =
        _valueAfter(arguments, '--cli') ?? environment['TYPEMATE_WHISPER_CLI'];
    final model =
        _valueAfter(arguments, '--model') ??
        environment['TYPEMATE_WHISPER_MODEL'];
    final audio = _valueAfter(arguments, '--audio');

    final executable = cli?.trim() ?? '';
    final modelPath = model?.trim() ?? '';
    final audioPath = audio?.trim() ?? '';

    if (executable.isEmpty || modelPath.isEmpty || audioPath.isEmpty) {
      return null;
    }

    return _BenchmarkOptions(
      executable: executable,
      modelPath: modelPath,
      audioPath: audioPath,
    );
  }

  static String? _valueAfter(List<String> arguments, String flag) {
    final index = arguments.indexOf(flag);
    if (index == -1 || index + 1 >= arguments.length) {
      return null;
    }
    return arguments[index + 1];
  }
}
