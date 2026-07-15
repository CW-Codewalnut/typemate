final RegExp _whitespacePattern = RegExp(r'\s+');

int wordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(_whitespacePattern).length;

bool isSilentAudioTranscript(String text) {
  return _silentAudioMarkers.contains(text.trim().toUpperCase());
}

int calculateAverageWordsPerMinute(int totalWords, Duration duration) {
  final minutes = duration.inMilliseconds / Duration.millisecondsPerMinute;
  if (minutes <= 0) {
    return 0;
  }
  return (totalWords / minutes).round();
}

String formatCompactNumber(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toString();
}

String formatShortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String formatTimeOfDay(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

const Set<String> _silentAudioMarkers = {
  '[BLANK_AUDIO]',
  '[SILENCE]',
  '[SILENT_AUDIO]',
};
