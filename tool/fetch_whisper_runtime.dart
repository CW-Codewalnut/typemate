import 'dart:io';

/// Provisions the speech runtimes that ship with TypeMate:
/// - models/parakeet-unified-en-0.6b-int8/ (English, in-process engine)
/// - models/parakeet-tdt-0.6b-v3-int8/ (24 multilingual languages)
/// - models/ggml-small-vaani-hindi-q6.bin (Hindi, Vaani fine-tune)
/// - models/ggml-hindi2hinglish-swift.bin (Hinglish, Oriserve Swift)
/// - models/ggml-silero-v5.1.2.bin (VAD)
/// - models/gtcrn_simple.onnx (optional noise suppression, GTCRN)
///
/// All are gitignored because they exceed practical git limits, so a fresh
/// clone runs this once. Release bundles copy both folders next to the
/// executable, then scripts/slim-speech-models.sh strips the large models
/// (they download on first use per selected language); dev builds keep
/// everything bundled so nothing downloads at runtime.
///
/// Runtime revision 2026-08-07 — CI caches models/ and bin/ keyed on this
/// file's hash, so bump this line whenever a hosted binary is replaced
/// under the same asset name (this revision: English moves to the
/// dedicated parakeet-unified-en-0.6b model — accent-robust,
/// corpus-verified — while v3 keeps the 24 multilingual languages; both
/// fetch here).
///
/// TYPEMATE_FETCH_SKIP_LARGE_MODELS=1 skips the multi-hundred-MB models
/// that only real dictation needs. CI e2e sets it: those runs inject mock
/// engines, and fetching ~1.2 GB per job was most of their wall time.
/// Release and dev builds must never set it.

class _ModelSpec {
  const _ModelSpec(
    this.fileName,
    this.url,
    this.expectedSizeBytes, {
    this.large = false,
  });

  final String fileName;
  final String url;
  final int expectedSizeBytes;

  /// Large models download on first use in production (see
  /// speech_model_catalog.dart) and are skippable in CI; the small
  /// always-bundled files (Silero VAD, GTCRN) are not.
  final bool large;
}

// Pinned to the same revisions as speech_model_catalog.dart, never to a
// branch: a bundled copy always wins over downloading, so fetching `main`
// here would let a dev checkout or a release bundle carry different bytes
// from what users download and what the corpus benchmark validated. Keep
// both files' revisions in lockstep.
const _parakeetBaseUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/2bda32ec70b097a55adaa07d9a7173915b43cc78';
const _parakeetEnglishBaseUrl =
    'https://huggingface.co/csukuangfj2/sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming/resolve/8c3a10fb13408c7a7054f6898958bf1c64a8d6c7';

const _models = [
  _ModelSpec(
    'parakeet-unified-en-0.6b-int8/encoder.int8.onnx',
    '$_parakeetEnglishBaseUrl/encoder.int8.onnx',
    654040552,
    large: true,
  ),
  _ModelSpec(
    'parakeet-unified-en-0.6b-int8/decoder.int8.onnx',
    '$_parakeetEnglishBaseUrl/decoder.int8.onnx',
    7257753,
    large: true,
  ),
  _ModelSpec(
    'parakeet-unified-en-0.6b-int8/joiner.int8.onnx',
    '$_parakeetEnglishBaseUrl/joiner.int8.onnx',
    1735860,
    large: true,
  ),
  _ModelSpec(
    'parakeet-unified-en-0.6b-int8/tokens.txt',
    '$_parakeetEnglishBaseUrl/tokens.txt',
    8952,
    large: true,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/encoder.int8.onnx',
    '$_parakeetBaseUrl/encoder.int8.onnx',
    652184281,
    large: true,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/decoder.int8.onnx',
    '$_parakeetBaseUrl/decoder.int8.onnx',
    11845275,
    large: true,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/joiner.int8.onnx',
    '$_parakeetBaseUrl/joiner.int8.onnx',
    6355277,
    large: true,
  ),
  _ModelSpec(
    'parakeet-tdt-0.6b-v3-int8/tokens.txt',
    '$_parakeetBaseUrl/tokens.txt',
    93939,
    large: true,
  ),
  _ModelSpec(
    'ggml-small-vaani-hindi-q6.bin',
    'https://huggingface.co/skaturanus/whisper-vaani-hindi-ggml/resolve/main/whisper-small-vaani-ggml-q6.bin',
    206820806,
    large: true,
  ),
  _ModelSpec(
    // GGML conversion of Oriserve/Whisper-Hindi2Hinglish-Swift (Apache-2.0),
    // hosted on this repo's releases because no public GGML exists.
    'ggml-hindi2hinglish-swift.bin',
    'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ggml-hindi2hinglish-swift.bin',
    147951465,
    large: true,
  ),
  // GGML q5_0 quantization of the AI4Bharat Vistaar Tamil fine-tune (MIT),
  // hosted on this repo's releases because no public GGML exists.
  _ModelSpec(
    'ggml-vistaar-tamil-small-q5_0.bin',
    'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ggml-vistaar-tamil-small-q5_0.bin',
    175209663,
    large: true,
  ),
  _ModelSpec(
    'ggml-silero-v5.1.2.bin',
    'https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin',
    885098,
  ),
  // GTCRN speech-enhancement model for the optional noise-suppression
  // toggle, run by the sherpa-onnx offline denoiser.
  _ModelSpec(
    'gtcrn_simple.onnx',
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/gtcrn_simple.onnx',
    535638,
  ),
];

Future<void> main(List<String> arguments) async {
  final force = arguments.contains('--force');
  final skipLarge =
      Platform.environment['TYPEMATE_FETCH_SKIP_LARGE_MODELS'] == '1';
  final client = HttpClient();
  try {
    // Fail fast: a broken download means the build cannot ship anyway, so
    // stop at the first error instead of burning time on the remaining
    // multi-hundred-MB fetches.
    for (final model in _models) {
      if (skipLarge && model.large) {
        stdout.writeln('model_skipped_large=${model.fileName}');
        continue;
      }
      await _fetchModel(client, model, force: force);
      if (exitCode != 0) {
        return;
      }
    }
    // Linux ships its helper tools too, so users install nothing: a static
    // ffmpeg for ALSA capture and xdotool (with its libxdo) for typing.
    // Windows and macOS need none of these (MediaFoundation / AVFoundation
    // capture, SendInput / System Events typing).
    if (Platform.isLinux) {
      await _fetchToolArchive(
        client,
        url:
            'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ffmpeg-7.0.2-linux-x64-static.tar.gz',
        targetDirectory: 'bin/ffmpeg',
        files: const ['ffmpeg'],
        force: force,
      );
      if (exitCode != 0) {
        return;
      }
      await _fetchToolArchive(
        client,
        url:
            'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/xdotool-linux-x64.tar.gz',
        targetDirectory: 'bin/xdotool',
        files: const ['xdotool', 'libxdo.so.3'],
        force: force,
      );
      if (exitCode != 0) {
        return;
      }
    }
  } finally {
    client.close();
  }
}

/// Downloads a tar.gz of prebuilt tool binaries and installs the listed
/// files into [targetDirectory], marking them executable.
Future<void> _fetchToolArchive(
  HttpClient client, {
  required String url,
  required String targetDirectory,
  required List<String> files,
  required bool force,
}) async {
  final target = Directory(targetDirectory);
  final missing = files
      .where((name) => !File('${target.path}/$name').existsSync())
      .toList();
  if (!force && missing.isEmpty) {
    stdout.writeln('tool_ready=${target.absolute.path}');
    return;
  }

  stdout.writeln('downloading=$url');
  final stagingDirectory = await Directory.systemTemp.createTemp(
    'typemate-tool',
  );
  try {
    final archive = File('${stagingDirectory.path}/tool.tar.gz');
    if (!await _downloadWithReleaseFallback(client, url, archive)) {
      exitCode = 1;
      return;
    }
    final extract = await Process.run('tar', [
      '-xf',
      archive.path,
      '-C',
      stagingDirectory.path,
    ]);
    if (extract.exitCode != 0) {
      stderr.writeln('tool_extract_failed=${extract.stderr}');
      exitCode = 1;
      return;
    }
    await target.create(recursive: true);
    for (final name in files) {
      final installed = await File(
        '${stagingDirectory.path}/$name',
      ).copy('${target.path}/$name');
      await _markExecutable(installed);
    }
    stdout.writeln('tool_ready=${target.absolute.path}');
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

Future<void> _markExecutable(File file) async {
  if (Platform.isWindows) {
    return;
  }
  await Process.run('chmod', ['+x', file.path]);
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
