/// Pinned Hugging Face revisions for the Parakeet exports, in a file with
/// NO imports on purpose: `tool/fetch_whisper_runtime.dart` runs as plain
/// `dart run` from the Windows CMake build, before Flutter is available,
/// so it cannot reach speech_model_catalog.dart (that pulls in the
/// provisioner, and through it `package:flutter`). Both sides import this
/// instead of keeping the same hash in two places.
///
/// Always a commit revision, never a branch: content at a commit is
/// immutable, so a resumed download can never append bytes of a newer
/// upload onto an older partial file, and a bundled copy (which always
/// wins over downloading) cannot drift from the bytes users fetch or from
/// the ones the corpus benchmark validated.
library;

/// NVIDIA Parakeet TDT 0.6B v3 int8 — the 24 multilingual languages.
const parakeetMultilingualModelRevision =
    '2bda32ec70b097a55adaa07d9a7173915b43cc78';

/// NVIDIA parakeet-unified-en-0.6b int8, non-streaming — English.
const parakeetEnglishModelRevision = '8c3a10fb13408c7a7054f6898958bf1c64a8d6c7';
