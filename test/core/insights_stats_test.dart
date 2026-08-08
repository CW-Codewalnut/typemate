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

  test('streaks survive a daylight-saving transition', () {
    // US DST ends 2026-11-01, so 2026-11-02 minus 24 hours is 23:00 on
    // 11-01, not midnight — with Duration arithmetic the day lookup missed
    // and the streak reset. Calendar arithmetic keeps it whole. (Harmless
    // in India, which has no DST, which is why it never showed locally.)
    final now = DateTime(2026, 11, 2, 12);
    final stats = InsightsStats.fromEntries([
      _entry('sunday words', DateTime(2026, 10, 31, 12)),
      _entry('dst day words', DateTime(2026, 11, 1, 12)),
      _entry('monday words', DateTime(2026, 11, 2, 9)),
    ], now: now);

    expect(stats.currentStreakDays, 3);
    expect(stats.longestStreakDays, 3);
    expect(stats.activeDays, 3);
  });

  test('the activity grid lands on real calendar days across DST', () {
    final now = DateTime(2026, 11, 2, 12);
    final stats = InsightsStats.fromEntries([
      _entry('dst day words', DateTime(2026, 11, 1, 12)),
    ], now: now);

    // Every cell must be local midnight; a 23:00 cell can never match a
    // day key, so its words silently read as zero.
    for (final cell in stats.activityCells) {
      expect(cell.date.hour, 0, reason: '${cell.date} is not local midnight');
    }
    final dstCell = stats.activityCells.firstWhere(
      (cell) => cell.date == DateTime(2026, 11, 1),
    );
    expect(dstCell.words, 3);
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
