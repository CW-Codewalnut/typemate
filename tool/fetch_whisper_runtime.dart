import 'dart:io';

/// Provisions the whisper runtime that ships with TypeMate:
/// - models/ggml-distil-small.en.bin (English)
/// - models/ggml-small-vaani-hindi-q6.bin (Hindi, Vaani fine-tune)
/// - models/ggml-hindi2hinglish-apex-q5_1.bin (Hinglish, Oriserve Apex)
/// - bin/whisper/ (whisper-cli and its DLLs, OpenBLAS build)
///
/// All are gitignored because they exceed practical git limits, so a fresh
/// clone runs this once. Release bundles copy both folders next to the
/// executable.

class _ModelSpec {
  const _ModelSpec(this.fileName, this.url, this.expectedSizeBytes);

  final String fileName;
  final String url;
  final int expectedSizeBytes;
}

const _models = [
  _ModelSpec(
    'ggml-distil-small.en.bin',
    'https://huggingface.co/distil-whisper/distil-small.en/resolve/main/ggml-distil-small.en.bin',
    336191657,
  ),
  _ModelSpec(
    'ggml-small-vaani-hindi-q6.bin',
    'https://huggingface.co/skaturanus/whisper-vaani-hindi-ggml/resolve/main/whisper-small-vaani-ggml-q6.bin',
    206820806,
  ),
  _ModelSpec(
    'ggml-hindi2hinglish-apex-q5_1.bin',
    'https://huggingface.co/voquill/whisper-hindi2hinglish-apex-ggml/resolve/main/ggml-hindi2hinglish-apex-q5_1.bin',
    624065675,
  ),
  _ModelSpec(
    'ggml-silero-v5.1.2.bin',
    'https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin',
    885098,
  ),
];

const whisperZipUrl =
    'https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-blas-bin-x64.zip';
const whisperCliFiles = [
  'whisper-cli.exe',
  'whisper.dll',
  'ggml.dll',
  'ggml-base.dll',
  'ggml-blas.dll',
  'libopenblas.dll',
];

Future<void> main(List<String> arguments) async {
  final force = arguments.contains('--force');
  final client = HttpClient();
  try {
    for (final model in _models) {
      await _fetchModel(client, model, force: force);
    }
    await _fetchCli(client, force: force);
  } finally {
    client.close();
  }
}

Future<void> _fetchModel(
  HttpClient client,
  _ModelSpec model, {
  required bool force,
}) async {
  final targetFile = File('models/${model.fileName}');
  if (!force &&
      targetFile.existsSync() &&
      targetFile.lengthSync() == model.expectedSizeBytes) {
    stdout.writeln('model_ready=${targetFile.absolute.path}');
    return;
  }

  stdout.writeln('downloading=${model.url}');
  await targetFile.parent.create(recursive: true);
  final partFile = File('${targetFile.path}.part');
  if (!await _download(client, model.url, partFile)) {
    exitCode = 1;
    return;
  }

  final downloadedSize = partFile.lengthSync();
  if (downloadedSize != model.expectedSizeBytes) {
    stderr.writeln(
      'model_download_incomplete expected=${model.expectedSizeBytes} '
      'actual=$downloadedSize',
    );
    await partFile.delete();
    exitCode = 1;
    return;
  }

  if (targetFile.existsSync()) {
    await targetFile.delete();
  }
  await partFile.rename(targetFile.path);
  stdout.writeln('model_ready=${targetFile.absolute.path}');
}

Future<void> _fetchCli(HttpClient client, {required bool force}) async {
  final targetDirectory = Directory('bin/whisper');
  final cliFile = File('${targetDirectory.path}/whisper-cli.exe');
  final missing = whisperCliFiles
      .where((name) => !File('${targetDirectory.path}/$name').existsSync())
      .toList();
  if (!force && missing.isEmpty) {
    stdout.writeln('cli_ready=${cliFile.absolute.path}');
    return;
  }

  stdout.writeln('downloading=$whisperZipUrl');
  final stagingDirectory = await Directory.systemTemp.createTemp(
    'typemate-whisper-cli',
  );
  try {
    final zipFile = File('${stagingDirectory.path}/whisper.zip');
    if (!await _download(client, whisperZipUrl, zipFile)) {
      exitCode = 1;
      return;
    }

    // Windows 10+ ships bsdtar, which extracts zip archives.
    final extract = await Process.run('tar', [
      '-xf',
      zipFile.path,
      '-C',
      stagingDirectory.path,
    ]);
    if (extract.exitCode != 0) {
      stderr.writeln('cli_extract_failed=${extract.stderr}');
      exitCode = 1;
      return;
    }

    await targetDirectory.create(recursive: true);
    final releaseDirectory = Directory('${stagingDirectory.path}/Release');
    for (final name in whisperCliFiles) {
      await File(
        '${releaseDirectory.path}/$name',
      ).copy('${targetDirectory.path}/$name');
    }
    await for (final entry in releaseDirectory.list()) {
      final baseName = entry.uri.pathSegments.last;
      if (entry is File && baseName.startsWith('ggml-cpu-')) {
        await entry.copy('${targetDirectory.path}/$baseName');
      }
    }
    stdout.writeln('cli_ready=${cliFile.absolute.path}');
  } finally {
    await stagingDirectory.delete(recursive: true);
  }
}

Future<bool> _download(HttpClient client, String url, File target) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    stderr.writeln('download_failed url=$url status=${response.statusCode}');
    return false;
  }
  final sink = target.openWrite();
  await response.pipe(sink);
  return true;
}
