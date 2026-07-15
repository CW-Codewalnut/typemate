class SpeechLanguageOption {
  const SpeechLanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}

/// Languages offered in the picker. TypeMate ships one validated model per
/// language: English (tiny.en, ~0.5s per clip), Hindi (Vaani fine-tune,
/// ~0.9s), and Hinglish (Oriserve Apex fine-tune that writes Hindi speech
/// in romanized Hinglish; turbo-sized, so noticeably slower at ~7s).
/// There is intentionally no Auto option — language auto-detection needs
/// the full encoder window, which is several times slower on laptop CPUs,
/// and it misfires often enough to produce garbage transcripts.
///
/// 'hinglish' is a TypeMate-internal code; the engine maps it to whisper's
/// 'hi' language flag and routes it to the Hinglish model.
///
/// Do not add a language back without validating real dictation quality
/// and latency with a dedicated model; a visible option must work.
const speechLanguageOptions = [
  SpeechLanguageOption(code: 'en', label: 'English'),
  SpeechLanguageOption(code: 'hi', label: 'Hindi'),
  SpeechLanguageOption(code: 'hinglish', label: 'Hinglish'),
];

SpeechLanguageOption? speechLanguageOptionForCode(String code) {
  final normalizedCode = code.trim().toLowerCase();
  for (final option in speechLanguageOptions) {
    if (option.code == normalizedCode) {
      return option;
    }
  }
  return null;
}

String? speechLanguageLabelForCode(String code) =>
    speechLanguageOptionForCode(code)?.label;
