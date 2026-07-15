class SpeechLanguageOption {
  const SpeechLanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}

/// Languages offered in the picker. Whisper technically accepts ~99
/// languages, but transcription quality varies enormously; this list is
/// curated to languages the bundled large-v3-turbo model transcribes well
/// (roughly <=15% word error rate on the FLEURS benchmark — at or better
/// than Hindi, which is the accepted quality floor). Thai and Cantonese are
/// excluded because the turbo variant degrades them hardest.
///
/// Do not add languages back without validating real dictation quality;
/// a visible option must work.
const speechLanguageOptions = [
  SpeechLanguageOption(code: 'auto', label: 'Auto'),
  SpeechLanguageOption(code: 'ar', label: 'Arabic'),
  SpeechLanguageOption(code: 'bg', label: 'Bulgarian'),
  SpeechLanguageOption(code: 'ca', label: 'Catalan'),
  SpeechLanguageOption(code: 'cs', label: 'Czech'),
  SpeechLanguageOption(code: 'da', label: 'Danish'),
  SpeechLanguageOption(code: 'de', label: 'German'),
  SpeechLanguageOption(code: 'el', label: 'Greek'),
  SpeechLanguageOption(code: 'en', label: 'English'),
  SpeechLanguageOption(code: 'es', label: 'Spanish'),
  SpeechLanguageOption(code: 'fi', label: 'Finnish'),
  SpeechLanguageOption(code: 'fr', label: 'French'),
  SpeechLanguageOption(code: 'hi', label: 'Hindi'),
  SpeechLanguageOption(code: 'hr', label: 'Croatian'),
  SpeechLanguageOption(code: 'hu', label: 'Hungarian'),
  SpeechLanguageOption(code: 'id', label: 'Indonesian'),
  SpeechLanguageOption(code: 'it', label: 'Italian'),
  SpeechLanguageOption(code: 'ja', label: 'Japanese'),
  SpeechLanguageOption(code: 'ko', label: 'Korean'),
  SpeechLanguageOption(code: 'ms', label: 'Malay'),
  SpeechLanguageOption(code: 'nl', label: 'Dutch'),
  SpeechLanguageOption(code: 'no', label: 'Norwegian'),
  SpeechLanguageOption(code: 'pl', label: 'Polish'),
  SpeechLanguageOption(code: 'pt', label: 'Portuguese'),
  SpeechLanguageOption(code: 'ro', label: 'Romanian'),
  SpeechLanguageOption(code: 'ru', label: 'Russian'),
  SpeechLanguageOption(code: 'sk', label: 'Slovak'),
  SpeechLanguageOption(code: 'sv', label: 'Swedish'),
  SpeechLanguageOption(code: 'tl', label: 'Tagalog'),
  SpeechLanguageOption(code: 'tr', label: 'Turkish'),
  SpeechLanguageOption(code: 'uk', label: 'Ukrainian'),
  SpeechLanguageOption(code: 'vi', label: 'Vietnamese'),
  SpeechLanguageOption(code: 'zh', label: 'Chinese'),
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
