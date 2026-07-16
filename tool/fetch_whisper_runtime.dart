import 'dart:io';

/// Provisions the speech runtimes that ship with TypeMate:
/// - models/parakeet-tdt-0.6b-v3-int8/ (English, resident sherpa server)
/// - models/ggml-small-vaani-hindi-q6.bin (Hindi, Vaani fine-tune)
/// - models/ggml-hindi2hinglish-swift.bin (Hinglish, Oriserve Swift)
/// - models/ggml-silero-v5.1.2.bin (VAD)
/// - bin/whisper/ (whisper-cli and its DLLs, OpenBLAS build)
/// - bin/sherpa/ (sherpa-onnx websocket server for the Parakeet model)
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

const _parakeetBaseUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main';

const _models = [
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/encoder.int8.onnx',
    '$_parakeetBaseUrl/encoder.int8.onnx',
    652184281,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/decoder.int8.onnx',
    '$_parakeetBaseUrl/decoder.int8.onnx',
    11845275,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/joiner.int8.onnx',
    '$_parakeetBaseUrl/joiner.int8.onnx',
    6355277,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/tokens.txt',
    '$_parakeetBaseUrl/tokens.txt',
    93939,
  ),
  _ModelSpec(
    'ggml-small-vaani-hindi-q6.bin',
    'https://huggingface.co/skaturanus/whisper-vaani-hindi-ggml/resolve/main/whisper-small-vaani-ggml-q6.bin',
    206820806,
  ),
  _ModelSpec(
    // GGML conversion of Oriserve/Whisper-Hindi2Hinglish-Swift (Apache-2.0),
    // hosted on this repo's releases because no public GGML exists.
    'ggml-hindi2hinglish-swift.bin',
    'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ggml-hindi2hinglish-swift.bin',
    147951465,
  ),
  // GGML q5_0 quantization of the AI4Bharat Vistaar Tamil fine-tune (MIT),
  // hosted on this repo's releases because no public GGML exists.
  _ModelSpec(
    'ggml-vistaar-tamil-small-q5_0.bin',
    'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ggml-vistaar-tamil-small-q5_0.bin',
    175209663,
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
  'whisper-server.exe',
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
    // Fail fast: a broken download means the build cannot ship anyway, so
    // stop at the first error instead of burning time on the remaining
    // multi-hundred-MB fetches.
    for (final model in _models) {
      await _fetchModel(client, model, force: force);
      if (exitCode != 0) {
        return;
      }
    }
    await _fetchCli(client, force: force);
    if (exitCode != 0) {
      return;
    }
    await _fetchSherpaServer(client, force: force);
  } finally {
    client.close();
  }
}

const _sherpaArchiveUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.4/'
    'sherpa-onnx-v1.13.4-win-x64-static-MD-MinSizeRel-no-tts.tar.bz2';
const _sherpaArchiveServerPath =
    'sherpa-onnx-v1.13.4-win-x64-static-MD-MinSizeRel-no-tts/bin/'
    'sherpa-onnx-offline-websocket-server.exe';
const _sherpaServerFileName = 'sherpa-onnx-offline-websocket-server.exe';

Future<void> _fetchSherpaServer(
  HttpClient client, {
  required bool force,
}) async {
  final targetFile = File('bin/sherpa/$_sherpaServerFileName');
  if (!force && targetFile.existsSync()) {
    stdout.writeln('sherpa_ready=${targetFile.absolute.path}');
    return;
  }

  stdout.writeln('downloading=$_sherpaArchiveUrl');
  final stagingDirectory = await Directory.systemTemp.createTemp(
    'typemate-sherpa',
  );
  try {
    final archive = File('${stagingDirectory.path}/sherpa.tar.bz2');
    if (!await _download(client, _sherpaArchiveUrl, archive)) {
      exitCode = 1;
      return;
    }

    final extract = await Process.run('tar', [
      '-xf',
      archive.path,
      '-C',
      stagingDirectory.path,
      _sherpaArchiveServerPath,
    ]);
    if (extract.exitCode != 0) {
      stderr.writeln('sherpa_extract_failed=${extract.stderr}');
      exitCode = 1;
      return;
    }

    await targetFile.parent.create(recursive: true);
    await File(
      '${stagingDirectory.path}/$_sherpaArchiveServerPath',
    ).copy(targetFile.path);
    stdout.writeln('sherpa_ready=${targetFile.absolute.path}');
  } finally {
    await stagingDirectory.delete(recursive: true);
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
  if (!await _downloadWithReleaseFallback(client, model.url, partFile)) {
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

const _repoReleasePrefix =
    'https://github.com/Ranjan-Bhagat/typemate/releases/download/';

/// While the repo is private its release assets 404 for anonymous requests,
/// so fall back to `gh release download`, which uses the local gh auth that
/// anyone able to clone the repo already has.
Future<bool> _downloadWithReleaseFallback(
  HttpClient client,
  String url,
  File target,
) async {
  if (await _download(client, url, target)) {
    return true;
  }
  if (!url.startsWith(_repoReleasePrefix)) {
    return false;
  }
  final segments = url.substring(_repoReleasePrefix.length).split('/');
  final tag = segments.first;
  final assetName = segments.last;
  stdout.writeln('retrying_via_gh=$assetName');
  final result = await Process.run('gh', [
    'release',
    'download',
    tag,
    '--repo',
    'Ranjan-Bhagat/typemate',
    '--pattern',
    assetName,
    '--output',
    target.path,
    '--clobber',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('gh_download_failed=${result.stderr}');
    return false;
  }
  return true;
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
