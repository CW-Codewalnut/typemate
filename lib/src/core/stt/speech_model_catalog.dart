import 'sherpa_parakeet_stt_engine.dart';
import 'stt_model_provisioner.dart';

/// Every downloadable speech model TypeMate uses, shared by the Android
/// first-run download and the desktop on-demand download. Each entry is
/// pinned: an immutable URL revision where possible, and always the exact
/// byte size and SHA-256 of the validated file — a corrupt model file
/// aborts the whole process inside the native loader, so nothing
/// unverified may ever reach it.

/// Same model directory names on every platform, so tooling and docs talk
/// about one model identity everywhere. English runs its own model:
/// parakeet-unified-en-0.6b (NVIDIA Open Model License — commercial use
/// and redistribution permitted) beat every candidate on the real-recording
/// accent corpus (test_assets/stt_benchmark, 2026-08 sweep: 4.2% vs v3's
/// 10.3% WER overall; Indian English 8.2% vs 13.3%) and its family has
/// streaming exports if live dictation preview ever lands — v3 keeps
/// serving the 24 multilingual languages it was adopted for.
const parakeetModelDirectoryName = 'parakeet-tdt-0.6b-v3-int8';
const parakeetEnglishModelDirectoryName = 'parakeet-unified-en-0.6b-int8';

/// The official sherpa-onnx exports of NVIDIA Parakeet 0.6B models
/// (TDT v3 int8 multilingual; unified-en int8 non-streaming for English).
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

// Hosted on csukuangfj2 (the sherpa-onnx maintainer's secondary account,
// where the newer exports land) rather than the usual csukuangfj — no
// k2-fsa-org copy of this export exists. Deliberate, and the revision +
// SHA-256 pins below make the host untrusted anyway: a byte that does not
// match never reaches the loader. Mirror to our own models-v1 release
// (as the Hinglish and Tamil GGMLs are) if that account ever goes away.
const _parakeetEnglishModelRevision =
    '8c3a10fb13408c7a7054f6898958bf1c64a8d6c7';
const _parakeetEnglishModelBaseUrl =
    'https://huggingface.co/csukuangfj2/sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming/resolve/$_parakeetEnglishModelRevision';

const _parakeetEnglishModelFileSizes = {
  'encoder.int8.onnx': 654040552,
  'decoder.int8.onnx': 7257753,
  'joiner.int8.onnx': 1735860,
  'tokens.txt': 8952,
};

/// SHA-256 of each file at the pinned revision (Hugging Face LFS oids;
/// tokens.txt hashed from the revision directly), byte-identical to the
/// files the 2026-08 accent-corpus benchmark validated. Update together
/// with the revision and the sizes above.
const _parakeetEnglishModelFileHashes = {
  'encoder.int8.onnx':
      '6716910b7a0833997fec7a410494c995d70124001a0e9b66d6370d6aced577e0',
  'decoder.int8.onnx':
      'a5e223392c90e75f8144cdb5eb95af7625db389e39edef2bd1a9c872b3298fe6',
  'joiner.int8.onnx':
      '869f43f7d24595c55581ad3bf249a935fb8a71389fbdaa7504b9f46f93140f8a',
  'tokens.txt':
      'dc0b4584ab2e4ddbf888425c076c61b736e7356a015250db7d307e6f1a8188ff',
};

final parakeetEnglishModelFiles = [
  for (final name in sherpaParakeetModelFileNames)
    SttModelFile(
      url: '$_parakeetEnglishModelBaseUrl/$name',
      relativePath: name,
      expectedBytes: _parakeetEnglishModelFileSizes[name]!,
      expectedSha256: _parakeetEnglishModelFileHashes[name]!,
    ),
];

/// The 25 languages served by a Parakeet engine: English by the dedicated
/// parakeet-unified-en model, the other 24 by the multilingual v3 with
/// automatic language detection.
const parakeetLanguageCodes = ['en', ...parakeetMultilingualLanguageCodes];

/// The 24 languages the multilingual v3 model serves — every Parakeet
/// language except English, which has its own model. Kept as its own
/// const so routing and provisioning never re-derive it by filtering
/// 'en' out of [parakeetLanguageCodes] at each call site.
const parakeetMultilingualLanguageCodes = [
  'bg', 'hr', 'cs', 'da', 'nl', 'et', 'fi', 'fr', 'de', 'el', 'hu', 'it', //
  'lv', 'lt', 'mt', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'es', 'sv', 'uk',
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

/// Silero VAD for whisper decoding: trims hold-to-talk silence so
/// whisper does not loop over the silent lead/tail. Bundled on desktop
/// (tiny); Android downloads it alongside a whisper language's model.
const sileroVadModelFile = SttModelFile(
  url:
      'https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin',
  relativePath: 'ggml-silero-v5.1.2.bin',
  expectedBytes: 885098,
  expectedSha256:
      '29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf',
);

/// GTCRN speech-enhancement model for the optional noise-suppression
/// toggle, run in-process through the sherpa_onnx plugin. Bundled on
/// desktop (tiny); Android downloads it alongside the Parakeet files.
const gtcrnModelFile = SttModelFile(
  url:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/gtcrn_simple.onnx',
  relativePath: 'gtcrn_simple.onnx',
  expectedBytes: 535638,
  expectedSha256:
      'e77603ac0c23dac3227dd2d7135b3a585cbee2679048aecfa886657d3ae1b534',
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
