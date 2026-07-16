class SpeechLanguageOption {
  const SpeechLanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}

/// Languages offered in the picker, each backed by a validated model:
///
/// - English and the European languages run on the resident Parakeet TDT
///   0.6B v3 server (~1s per clip, automatic language detection, native
///   punctuation). Parakeet supports exactly these 25 languages.
/// - Hindi uses the Vaani small whisper fine-tune (~2.8s).
/// - Hinglish uses the Oriserve Swift whisper fine-tune (base-sized,
///   ~1.2s), which writes Hindi speech as romanized Hinglish.
/// - Tamil uses an AI4Bharat Vistaar fine-tune on its own resident whisper
///   server. Telugu, Kannada, and Gujarati were evaluated and dropped:
///   their checkpoints hallucinate or corrupt output non-deterministically,
///   which fails the quality bar below. Marathi validated but was cut for
///   install size (medium-only checkpoint, ~514 MB).
///
/// There is no Auto option in the picker; within the Parakeet languages the
/// model detects the spoken language on its own.
///
/// 'hinglish' is a TypeMate-internal code; the engine maps it to whisper's
/// 'hi' language flag and routes it to the Hinglish model.
///
/// Do not add a language without a validated model for it (quality and
/// latency); a visible option must work.
const speechLanguageOptions = [
  SpeechLanguageOption(code: 'en', label: 'English'),
  SpeechLanguageOption(code: 'hi', label: 'Hindi'),
  SpeechLanguageOption(code: 'hinglish', label: 'Hinglish'),
  SpeechLanguageOption(code: 'bg', label: 'Bulgarian'),
  SpeechLanguageOption(code: 'ta', label: 'Tamil'),
  SpeechLanguageOption(code: 'hr', label: 'Croatian'),
  SpeechLanguageOption(code: 'cs', label: 'Czech'),
  SpeechLanguageOption(code: 'da', label: 'Danish'),
  SpeechLanguageOption(code: 'nl', label: 'Dutch'),
  SpeechLanguageOption(code: 'et', label: 'Estonian'),
  SpeechLanguageOption(code: 'fi', label: 'Finnish'),
  SpeechLanguageOption(code: 'fr', label: 'French'),
  SpeechLanguageOption(code: 'de', label: 'German'),
  SpeechLanguageOption(code: 'el', label: 'Greek'),
  SpeechLanguageOption(code: 'hu', label: 'Hungarian'),
  SpeechLanguageOption(code: 'it', label: 'Italian'),
  SpeechLanguageOption(code: 'lv', label: 'Latvian'),
  SpeechLanguageOption(code: 'lt', label: 'Lithuanian'),
  SpeechLanguageOption(code: 'mt', label: 'Maltese'),
  SpeechLanguageOption(code: 'pl', label: 'Polish'),
  SpeechLanguageOption(code: 'pt', label: 'Portuguese'),
  SpeechLanguageOption(code: 'ro', label: 'Romanian'),
  SpeechLanguageOption(code: 'ru', label: 'Russian'),
  SpeechLanguageOption(code: 'sk', label: 'Slovak'),
  SpeechLanguageOption(code: 'sl', label: 'Slovenian'),
  SpeechLanguageOption(code: 'es', label: 'Spanish'),
  SpeechLanguageOption(code: 'sv', label: 'Swedish'),
  SpeechLanguageOption(code: 'uk', label: 'Ukrainian'),
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
