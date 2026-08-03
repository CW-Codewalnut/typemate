import 'sherpa_parakeet_stt_engine.dart';
import 'stt_model_provisioner.dart';

/// Every downloadable speech model TypeMate uses, shared by the Android
/// first-run download and the desktop on-demand download. Each entry is
/// pinned: an immutable URL revision where possible, and always the exact
/// byte size and SHA-256 of the validated file — a corrupt model file
/// aborts the whole process inside the native loader, so nothing
/// unverified may ever reach it.

/// Same model directory name on every platform, so tooling and docs talk
/// about one model identity everywhere.
const parakeetModelDirectoryName = 'parakeet-tdt-0.6b-v3-int8';

/// The official sherpa-onnx export of NVIDIA Parakeet TDT 0.6B v3 int8.
/// Individual files (not the .tar.bz2 archive) so the download streams
/// straight to disk with HTTP-range resume and no archive extraction.
///
/// PINNED to a commit revision, never a branch: content at a commit is
/// immutable, so a resume can never append bytes of a newer upload onto
/// an older partial file, and we ship exactly the bytes that were
/// validated — not whatever `main` points at later. The byte sizes come
/// from the same revision and gate the rename-to-complete.
const _parakeetModelRevision = '2bda32ec70b097a55adaa07d9a7173915b43cc78';
const _parakeetModelBaseUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/$_parakeetModelRevision';

const _parakeetModelFileSizes = {
  'encoder.int8.onnx': 652184281,
  'decoder.int8.onnx': 11845275,
  'joiner.int8.onnx': 6355277,
  'tokens.txt': 93939,
};

/// SHA-256 of each file at the pinned revision (Hugging Face LFS oids;
/// tokens.txt hashed from the revision directly). Update together with
/// the revision and the sizes above.
const _parakeetModelFileHashes = {
  'encoder.int8.onnx':
      'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
  'decoder.int8.onnx':
      '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
  'joiner.int8.onnx':
      '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
  'tokens.txt':
      'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
};

final parakeetModelFiles = [
  for (final name in sherpaParakeetModelFileNames)
    SttModelFile(
      url: '$_parakeetModelBaseUrl/$name',
      relativePath: name,
      expectedBytes: _parakeetModelFileSizes[name]!,
      expectedSha256: _parakeetModelFileHashes[name]!,
    ),
];

/// The 25 languages Parakeet TDT 0.6B v3 transcribes, with automatic
/// language detection — every one is served by the same model.
const parakeetLanguageCodes = [
  'en', 'bg', 'hr', 'cs', 'da', 'nl', 'et', 'fi', 'fr', 'de', 'el', 'hu', //
  'it', 'lv', 'lt', 'mt', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'es', 'sv',
  'uk',
];

/// Vaani small fine-tune for Hindi (noise-robust, Devanagari output),
/// pinned to the Hugging Face revision whose LFS hash was validated.
const vaaniHindiModelFile = SttModelFile(
  url:
      'https://huggingface.co/skaturanus/whisper-vaani-hindi-ggml/resolve/a5dadfba594c5c5f16e151d8917574793342d7fc/whisper-small-vaani-ggml-q6.bin',
  relativePath: 'ggml-small-vaani-hindi-q6.bin',
  expectedBytes: 206820806,
  expectedSha256:
      '0c177e83f5924fcf9e94e729038314e1ba80e3e750ada5d379e977d79cd1ba74',
);

/// GGML conversion of Oriserve/Whisper-Hindi2Hinglish-Swift (Apache-2.0),
/// hosted on this repo's releases because no public GGML exists. Release
/// assets are only ever replaced deliberately; the hash gates that too.
const hinglishSwiftModelFile = SttModelFile(
  url:
      'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ggml-hindi2hinglish-swift.bin',
  relativePath: 'ggml-hindi2hinglish-swift.bin',
  expectedBytes: 147951465,
  expectedSha256:
      '4e9caa5f4b0416824d7cbeec22a37ef78a05e4b0189864eed65cd56d81c6b0a8',
);

/// GGML q5_0 quantization of the AI4Bharat Vistaar Tamil fine-tune (MIT),
/// hosted on this repo's releases because no public GGML exists.
const vistaarTamilModelFile = SttModelFile(
  url:
      'https://github.com/Ranjan-Bhagat/typemate/releases/download/models-v1/ggml-vistaar-tamil-small-q5_0.bin',
  relativePath: 'ggml-vistaar-tamil-small-q5_0.bin',
  expectedBytes: 175209663,
  expectedSha256:
      'ca36914f822c0b60c04c3e75904483ab3e683e6f5ae8e6cf36751ed695cd7bda',
);
