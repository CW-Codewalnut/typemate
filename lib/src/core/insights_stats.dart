import '../utils/text_metrics.dart';
import 'dictation_history_controller.dart';

const int activityGridColumns = 12;

class InsightsStats {
  const InsightsStats({
    required this.totalWords,
    required this.averageWordsPerMinute,
    required this.dictationCount,
    required this.todayWords,
    required this.previousSevenDaysWords,
    required this.olderWords,
    required this.activeDays,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.activityCells,
  });

  final int totalWords;
  final int averageWordsPerMinute;
  final int dictationCount;
  final int todayWords;
  final int previousSevenDaysWords;
  final int olderWords;
  final int activeDays;
  final int currentStreakDays;
  final int longestStreakDays;
  final List<ActivityCellData> activityCells;

  int get averageWordsPerSession =>
      dictationCount == 0 ? 0 : (totalWords / dictationCount).round();

  static InsightsStats fromEntries(
    List<DictationHistoryEntry> entries, {
    DateTime? now,
  }) {
    final today = _dateOnly((now ?? DateTime.now()).toLocal());
    final wordsByDay = <DateTime, int>{};
    var totalWords = 0;
    var totalDuration = Duration.zero;

    for (final entry in entries) {
      final words = wordCount(entry.text);
      totalWords += words;
      totalDuration += entry.duration;
      final day = _dateOnly(entry.createdAt.toLocal());
      wordsByDay[day] = (wordsByDay[day] ?? 0) + words;
    }

    final previousSevenDayStart = today.subtract(const Duration(days: 7));
    return InsightsStats(
      totalWords: totalWords,
      averageWordsPerMinute: calculateAverageWordsPerMinute(
        totalWords,
        totalDuration,
      ),
      dictationCount: entries.length,
      todayWords: wordsByDay[today] ?? 0,
      previousSevenDaysWords: _sumWordsBetween(
        wordsByDay,
        startInclusive: previousSevenDayStart,
        endExclusive: today,
      ),
      olderWords: _sumWordsBefore(wordsByDay, previousSevenDayStart),
      activeDays: wordsByDay.length,
      currentStreakDays: _currentStreak(wordsByDay.keys, today),
      longestStreakDays: _longestStreak(wordsByDay.keys),
      activityCells: _activityCells(wordsByDay, today),
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static int _sumWordsBetween(
    Map<DateTime, int> wordsByDay, {
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    return wordsByDay.entries
        .where(
          (entry) =>
              !entry.key.isBefore(startInclusive) &&
              entry.key.isBefore(endExclusive),
        )
        .fold(0, (total, entry) => total + entry.value);
  }

  static int _sumWordsBefore(Map<DateTime, int> wordsByDay, DateTime date) {
    return wordsByDay.entries
        .where((entry) => entry.key.isBefore(date))
        .fold(0, (total, entry) => total + entry.value);
  }

  static int _currentStreak(Iterable<DateTime> days, DateTime today) {
    final daySet = days.toSet();
    if (!daySet.contains(today)) {
      return 0;
    }

    var streak = 0;
    var cursor = today;
    while (daySet.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _longestStreak(Iterable<DateTime> days) {
    final sortedDays = days.toList()..sort();
    var longest = 0;
    var current = 0;
    DateTime? previous;

    for (final day in sortedDays) {
      if (previous == null || day.difference(previous).inDays == 1) {
        current++;
      } else if (day != previous) {
        current = 1;
      }
      if (current > longest) {
        longest = current;
      }
      previous = day;
    }
    return longest;
  }

  static List<ActivityCellData> _activityCells(
    Map<DateTime, int> wordsByDay,
    DateTime today,
  ) {
    final start = today.subtract(
      Duration(
        days:
            (today.weekday % DateTime.daysPerWeek) +
            ((activityGridColumns - 1) * DateTime.daysPerWeek),
      ),
    );
    final maxWords = wordsByDay.values.fold(
      0,
      (max, words) => words > max ? words : max,
    );

    return [
      for (var row = 0; row < DateTime.daysPerWeek; row++)
        for (var column = 0; column < activityGridColumns; column++)
          _activityCell(
            wordsByDay,
            start.add(Duration(days: column * DateTime.daysPerWeek + row)),
            maxWords,
          ),
    ];
  }

  static ActivityCellData _activityCell(
    Map<DateTime, int> wordsByDay,
    DateTime date,
    int maxWords,
  ) {
    final words = wordsByDay[date] ?? 0;
    return ActivityCellData(
      date: date,
      words: words,
      intensity: _activityIntensity(words, maxWords),
    );
  }

  static int _activityIntensity(int words, int maxWords) {
    if (words <= 0 || maxWords <= 0) return 0;
    if (words >= maxWords) return 3;
    if (words >= (maxWords * 0.5).ceil()) return 2;
    return 1;
  }
}

class ActivityCellData {
  const ActivityCellData({
    required this.date,
    required this.words,
    required this.intensity,
  });

  final DateTime date;
  final int words;
  final int intensity;
}
