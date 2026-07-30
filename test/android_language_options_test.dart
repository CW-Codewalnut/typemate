import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/models/speech_language_options.dart';

void main() {
  test('Android offers only the Parakeet languages', () {
    final codes = [
      for (final option in androidSpeechLanguageOptions) option.code,
    ];

    // The whisper-server languages need processes Android cannot spawn.
    expect(codes, isNot(contains('hi')));
    expect(codes, isNot(contains('hinglish')));
    expect(codes, isNot(contains('ta')));
    expect(codes, contains('en'));
    expect(
      codes,
      hasLength(speechLanguageOptions.length - 3),
      reason: 'Every other curated language stays available.',
    );
  });
}
