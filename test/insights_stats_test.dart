import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/dictation_history_controller.dart';
import 'package:typemate/src/core/insights_stats.dart';

void main() {
  test('calculates usage buckets, pace, and streaks from explicit dates', () {
    final now = DateTime(2026, 7, 15, 12);
    final stats = InsightsStats.fromEntries([
      _entry('today words here now', now, const Duration(seconds: 30)),
      _entry('yesterday words', now.subtract(const Duration(days: 1))),
      _entry('two days active', now.subtract(const Duration(days: 2))),
      _entry('older archived words', now.subtract(const Duration(days: 9))),
    ], now: now);

    expect(stats.totalWords, 12);
    expect(stats.averageWordsPerMinute, 24);
    expect(stats.dictationCount, 4);
    expect(stats.todayWords, 4);
    expect(stats.previousSevenDaysWords, 5);
    expect(stats.olderWords, 3);
    expect(stats.activeDays, 4);
    expect(stats.currentStreakDays, 3);
    expect(stats.longestStreakDays, 3);
    expect(
      stats.activityCells,
      hasLength(DateTime.daysPerWeek * activityGridColumns),
    );
  });

  test('current streak is zero when there is no activity today', () {
    final now = DateTime(2026, 7, 15, 12);
    final stats = InsightsStats.fromEntries([
      _entry('previous day words', now.subtract(const Duration(days: 1))),
    ], now: now);

    expect(stats.currentStreakDays, 0);
    expect(stats.longestStreakDays, 1);
  });
}

DictationHistoryEntry _entry(
  String text,
  DateTime createdAt, [
  Duration duration = Duration.zero,
]) {
  return DictationHistoryEntry(
    text: text,
    createdAt: createdAt,
    duration: duration,
  );
}
