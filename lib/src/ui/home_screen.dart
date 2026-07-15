import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/ffmpeg_microphone_discovery.dart';
import '../core/dictation_controller.dart';
import '../core/dictation_history_controller.dart';
import '../core/hold_shortcut_controller.dart';
import '../core/microphone_settings_controller.dart';
import '../core/speech_settings_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.historyController,
    required this.microphoneController,
    required this.speechSettingsController,
    this.shortcutController,
  });

  final DictationController controller;
  final DictationHistoryController historyController;
  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.prepare();
    widget.microphoneController.loadMicrophones();
    widget.historyController.load();
    widget.speechSettingsController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.historyController,
        widget.microphoneController,
        widget.speechSettingsController,
        if (widget.shortcutController != null) widget.shortcutController!,
      ]),
      builder: (context, _) {
        final page = switch (_selectedIndex) {
          0 => _HistoryPage(
            historyController: widget.historyController,
            shortcutController: widget.shortcutController,
          ),
          1 => _InsightsPage(historyController: widget.historyController),
          _ => _SettingsPage(
            microphoneController: widget.microphoneController,
            speechSettingsController: widget.speechSettingsController,
            shortcutController: widget.shortcutController,
          ),
        };

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.history),
                      selectedIcon: Icon(Icons.history_toggle_off),
                      label: Text('History'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights),
                      label: Text('Insights'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({
    required this.historyController,
    this.shortcutController,
  });

  final DictationHistoryController historyController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ScrollConfiguration(
          key: const Key('history-scrollbar-hidden'),
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final historyContent = Column(
                  key: const Key('history-main-column'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Speech history',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ShortcutInstructionCard(
                      instruction: _shortcutInstruction(shortcutController),
                    ),
                    if (historyController.entries.isNotEmpty) ...[
                      const SizedBox(height: 34),
                      Row(
                        children: [
                          Text(
                            'TODAY',
                            key: const Key('history-section-today'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: historyController.clear,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Clear history'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (historyController.entries.isEmpty)
                      const SizedBox(height: 28),
                    if (historyController.isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (historyController.entries.isEmpty)
                      const _EmptyHistoryCard()
                    else
                      for (final entry in historyController.entries)
                        _HistoryEntryCard(entry: entry),
                  ],
                );

                final reportCard = SizedBox(
                  key: const Key('history-stats-rail'),
                  width: 300,
                  child: _HistoryReportCard(
                    totalWords: historyController.totalWords,
                    wordsPerMinute: historyController.averageWordsPerMinute,
                  ),
                );

                if (constraints.maxWidth < 780) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      historyContent,
                      const SizedBox(height: 24),
                      reportCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: historyContent),
                    const SizedBox(width: 28),
                    reportCard,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightsPage extends StatelessWidget {
  const _InsightsPage({required this.historyController});

  final DictationHistoryController historyController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _InsightsStats.fromEntries(historyController.entries);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ScrollConfiguration(
          key: const Key('insights-scrollbar-hidden'),
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            key: const Key('insights-page'),
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Insights',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _LocalHistoryBadge(entryCount: stats.dictationCount),
                  ],
                ),
                const SizedBox(height: 30),
                const _InsightsTabs(),
                const Divider(height: 30),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final cards = [
                      _InsightStatCard(
                        value: stats.averageWordsPerMinute.toString(),
                        label: 'Words per minute',
                        child: _InsightGauge(
                          percent: _topPercent(stats.averageWordsPerMinute),
                        ),
                      ),
                      _InsightStatCard(
                        value: stats.dictationCount.toString(),
                        label: 'Dictation sessions',
                        child: _DictationSessionSummary(stats: stats),
                      ),
                      _InsightStatCard(
                        value: _formatMetric(stats.totalWords),
                        label: 'Total words dictated',
                        child: _DeviceWordsSummary(stats: stats),
                      ),
                    ];

                    if (!wide) {
                      return Column(
                        children: [
                          for (final card in cards) ...[
                            SizedBox(width: double.infinity, child: card),
                            const SizedBox(height: 16),
                          ],
                          _InsightsBottomStack(stats: stats),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 20),
                            Expanded(child: cards[1]),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: cards[2]),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _InsightsBottomStack(stats: stats),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _topPercent(int wordsPerMinute) {
    if (wordsPerMinute >= 110) return 1;
    if (wordsPerMinute >= 80) return 5;
    if (wordsPerMinute >= 50) return 15;
    if (wordsPerMinute > 0) return 25;
    return 0;
  }
}

class _InsightsStats {
  const _InsightsStats({
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
  final List<_ActivityCellData> activityCells;

  int get averageWordsPerSession =>
      dictationCount == 0 ? 0 : (totalWords / dictationCount).round();

  static _InsightsStats fromEntries(List<DictationHistoryEntry> entries) {
    final today = DateUtils.dateOnly(DateTime.now());
    final wordsByDay = <DateTime, int>{};
    var totalWords = 0;
    var totalDuration = Duration.zero;

    for (final entry in entries) {
      final words = _wordCount(entry.text);
      totalWords += words;
      totalDuration += entry.duration;
      final day = DateUtils.dateOnly(entry.createdAt.toLocal());
      wordsByDay[day] = (wordsByDay[day] ?? 0) + words;
    }

    final minutes =
        totalDuration.inMilliseconds / Duration.millisecondsPerMinute;
    final averageWordsPerMinute = minutes <= 0
        ? 0
        : (totalWords / minutes).round();
    final previousSevenDayStart = today.subtract(const Duration(days: 7));
    var previousSevenDaysWords = 0;
    var olderWords = 0;

    for (final entry in wordsByDay.entries) {
      if (entry.key.isBefore(previousSevenDayStart)) {
        olderWords += entry.value;
      } else if (entry.key.isBefore(today)) {
        previousSevenDaysWords += entry.value;
      }
    }

    return _InsightsStats(
      totalWords: totalWords,
      averageWordsPerMinute: averageWordsPerMinute,
      dictationCount: entries.length,
      todayWords: wordsByDay[today] ?? 0,
      previousSevenDaysWords: previousSevenDaysWords,
      olderWords: olderWords,
      activeDays: wordsByDay.length,
      currentStreakDays: _currentStreak(wordsByDay.keys, today),
      longestStreakDays: _longestStreak(wordsByDay.keys),
      activityCells: _activityCells(wordsByDay, today),
    );
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

  static List<_ActivityCellData> _activityCells(
    Map<DateTime, int> wordsByDay,
    DateTime today,
  ) {
    const columns = 12;
    final start = today.subtract(
      Duration(
        days: (today.weekday % DateTime.daysPerWeek) + ((columns - 1) * 7),
      ),
    );
    final maxWords = wordsByDay.values.fold(
      0,
      (max, words) => words > max ? words : max,
    );

    return [
      for (var row = 0; row < DateTime.daysPerWeek; row++)
        for (var column = 0; column < columns; column++)
          _activityCell(
            wordsByDay,
            start.add(Duration(days: column * DateTime.daysPerWeek + row)),
            maxWords,
          ),
    ];
  }

  static _ActivityCellData _activityCell(
    Map<DateTime, int> wordsByDay,
    DateTime date,
    int maxWords,
  ) {
    final words = wordsByDay[date] ?? 0;
    return _ActivityCellData(
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

class _ActivityCellData {
  const _ActivityCellData({
    required this.date,
    required this.words,
    required this.intensity,
  });

  final DateTime date;
  final int words;
  final int intensity;
}

class _LocalHistoryBadge extends StatelessWidget {
  const _LocalHistoryBadge({required this.entryCount});

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          '$entryCount local ${entryCount == 1 ? 'dictation' : 'dictations'}',
          key: const Key('insights-local-history-count'),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _InsightsTabs extends StatelessWidget {
  const _InsightsTabs();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tab(String label, {bool selected = false}) {
      return Padding(
        padding: const EdgeInsets.only(right: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 2,
              width: selected ? 74 : 0,
              color: theme.colorScheme.onSurface,
            ),
          ],
        ),
      );
    }

    return Row(children: [tab('Your Usage', selected: true)]);
  }
}

class _InsightStatCard extends StatelessWidget {
  const _InsightStatCard({
    required this.value,
    required this.label,
    required this.child,
  });

  final String value;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(height: 120, child: child),
          ],
        ),
      ),
    );
  }
}

class _InsightGauge extends StatelessWidget {
  const _InsightGauge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SizedBox(
        width: 156,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GaugePainter(color: theme.colorScheme.primary),
              ),
            ),
            Positioned(
              top: 36,
              child: Column(
                children: [
                  Text(
                    percent == 0 ? 'No pace yet' : 'Top',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    percent == 0 ? '0%' : '$percent%',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(16, 12, size.width - 32, size.height * 1.35);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 3.14, 3.14, false, paint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DictationSessionSummary extends StatelessWidget {
  const _DictationSessionSummary({required this.stats});

  final _InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        _SummaryLine(
          value: _formatMetric(stats.averageWordsPerSession),
          label: 'avg words/session',
        ),
        const SizedBox(height: 8),
        _SummaryLine(
          value: stats.activeDays.toString(),
          label: stats.activeDays == 1 ? 'active day' : 'active days',
        ),
      ],
    );
  }
}

class _DeviceWordsSummary extends StatelessWidget {
  const _DeviceWordsSummary({required this.stats});

  final _InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Divider(),
        Row(
          children: [
            const Icon(Icons.desktop_windows_outlined, size: 18),
            const SizedBox(width: 8),
            Text(
              'Desktop',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${_formatMetric(stats.todayWords)} today',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('${_formatMetric(stats.totalWords)} words from local history'),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$value $label',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _InsightsBottomStack extends StatelessWidget {
  const _InsightsBottomStack({required this.stats});

  final _InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              _DesktopUsageCard(stats: stats),
              const SizedBox(height: 16),
              _StreakCard(stats: stats),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DesktopUsageCard(stats: stats)),
            const SizedBox(width: 20),
            Expanded(child: _StreakCard(stats: stats)),
          ],
        );
      },
    );
  }
}

class _DesktopUsageCard extends StatelessWidget {
  const _DesktopUsageCard({required this.stats});

  final _InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      _UsageRow(
        Icons.today_outlined,
        'Today',
        _percent(stats.todayWords, stats.totalWords),
        stats.todayWords,
      ),
      _UsageRow(
        Icons.date_range_outlined,
        'Last 7 days',
        _percent(stats.previousSevenDaysWords, stats.totalWords),
        stats.previousSevenDaysWords,
      ),
      _UsageRow(
        Icons.history_outlined,
        'Older history',
        _percent(stats.olderWords, stats.totalWords),
        stats.olderWords,
      ),
    ];

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dictation activity',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'TOTAL SESSIONS | ${stats.dictationCount}',
                    key: const Key('insights-total-sessions'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final row in rows) _UsageBar(row: row),
          ],
        ),
      ),
    );
  }

  int _percent(int value, int total) {
    if (value <= 0 || total <= 0) return 0;
    return ((value / total) * 100).round().clamp(1, 100);
  }
}

class _UsageRow {
  const _UsageRow(this.icon, this.label, this.percent, this.words);

  final IconData icon;
  final String label;
  final int percent;
  final int words;
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.row});

  final _UsageRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(row.icon, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: row.percent / 100,
                minHeight: 28,
                backgroundColor: theme.colorScheme.surface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: Text(
              '${_formatMetric(row.words)} ${row.label}'.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.stats});

  final _InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentStreakLabel = stats.currentStreakDays == 1
        ? '1 day streak'
        : '${stats.currentStreakDays} day streak';
    final longestStreakLabel = stats.longestStreakDays == 1
        ? 'LONGEST STREAK | 1 DAY'
        : 'LONGEST STREAK | ${stats.longestStreakDays} DAYS';

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentStreakLabel,
                    key: const Key('insights-current-streak'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    longestStreakLabel,
                    key: const Key('insights-longest-streak'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _StreakGrid(cells: stats.activityCells),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('More', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                for (final color in [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.65),
                  theme.colorScheme.primary.withValues(alpha: 0.35),
                ]) ...[
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text('Less', style: theme.textTheme.labelMedium),
                const Spacer(),
                Text('Last 12 weeks', style: theme.textTheme.labelMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakGrid extends StatelessWidget {
  const _StreakGrid({required this.cells});

  final List<_ActivityCellData> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Column(
      key: const Key('insights-streak-grid'),
      children: [
        for (var row = 0; row < labels.length; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(labels[row], style: theme.textTheme.labelSmall),
                ),
                for (var col = 0; col < 12; col++) ...[
                  _StreakCell(cell: cells[row * 12 + col]),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _StreakCell extends StatelessWidget {
  const _StreakCell({required this.cell});

  final _ActivityCellData cell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (cell.intensity) {
      0 => theme.colorScheme.surface,
      1 => theme.colorScheme.primary.withValues(alpha: 0.28),
      2 => theme.colorScheme.primary.withValues(alpha: 0.58),
      _ => theme.colorScheme.primary,
    };
    return Tooltip(
      message:
          '${_formatShortDate(cell.date)}: ${_formatMetric(cell.words)} words',
      child: Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

int _wordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

String _formatShortDate(DateTime date) {
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

String _formatMetric(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toString();
}

class _HistoryReportCard extends StatelessWidget {
  const _HistoryReportCard({
    required this.totalWords,
    required this.wordsPerMinute,
  });

  final int totalWords;
  final int wordsPerMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('history-report-card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HistoryMetricRow(
              value: _formatMetric(totalWords),
              label: 'total words',
            ),
            const SizedBox(height: 18),
            _HistoryMetricRow(value: wordsPerMinute.toString(), label: 'wpm'),
          ],
        ),
      ),
    );
  }

  String _formatMetric(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}

class _HistoryMetricRow extends StatelessWidget {
  const _HistoryMetricRow({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShortcutInstructionCard extends StatelessWidget {
  const _ShortcutInstructionCard({required this.instruction});

  final String instruction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_voice, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                instruction,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortcutInstruction(HoldShortcutController? shortcutController) {
  final shortcut = shortcutController?.shortcut;
  if (shortcut == null) {
    return 'Press and hold your shortcut and start speaking.';
  }
  return 'Press and hold ${shortcut.label} and start speaking.';
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.microphoneController,
    required this.speechSettingsController,
    this.shortcutController,
  });

  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Text(
              'Settings',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            _SpeechSettingsPanel(controller: speechSettingsController),
            const SizedBox(height: 24),
            _MicrophoneSelectionPanel(controller: microphoneController),
            if (shortcutController != null) ...[
              const SizedBox(height: 24),
              _ShortcutSettingsPanel(controller: shortcutController!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShortcutSettingsPanel extends StatefulWidget {
  const _ShortcutSettingsPanel({required this.controller});

  final HoldShortcutController controller;

  @override
  State<_ShortcutSettingsPanel> createState() => _ShortcutSettingsPanelState();
}

class _ShortcutSettingsPanelState extends State<_ShortcutSettingsPanel> {
  final FocusNode _recordFocusNode = FocusNode(debugLabel: 'shortcut-recorder');
  final Set<int> _recordedVirtualKeyCodes = {};
  bool _isRecording = false;
  String _recordingLabel = 'Click record, then press your shortcut.';

  @override
  void dispose() {
    _recordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;

    return KeyboardListener(
      focusNode: _recordFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    controller.isRegistered
                        ? Icons.keyboard_command_key
                        : Icons.keyboard_command_key_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shortcut', style: theme.textTheme.titleMedium),
                        Text(controller.statusMessage),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Current shortcut', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(controller.shortcut.label),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_circle_outlined
                          : Icons.keyboard,
                    ),
                    label: Text(
                      _isRecording ? 'Stop recording' : 'Record shortcut',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.resetShortcutToDefault,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset to default'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isRecording
                    ? _recordingLabel
                    : 'Press up to 3 keys. TypeMate saves automatically at 3 keys, or click Stop recording to save fewer keys.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startRecording() {
    setState(() {
      _recordedVirtualKeyCodes.clear();
      _isRecording = true;
      _recordingLabel = 'Waiting for shortcut keys...';
    });
    _recordFocusNode.requestFocus();
  }

  void _stopRecording() {
    if (_recordedVirtualKeyCodes.isEmpty) {
      setState(() {
        _isRecording = false;
        _recordingLabel = 'No shortcut recorded.';
      });
      return;
    }

    _saveRecordedShortcut();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!_isRecording || event is! KeyDownEvent) {
      return;
    }

    final pressedKeyCodes = HardwareKeyboard.instance.logicalKeysPressed
        .map(_virtualKeyCodeForLogicalKey)
        .whereType<int>();
    final eventKeyCode = _virtualKeyCodeForLogicalKey(event.logicalKey);
    setState(() {
      _recordedVirtualKeyCodes.addAll(pressedKeyCodes);
      if (eventKeyCode != null) {
        _recordedVirtualKeyCodes.add(eventKeyCode);
      }
      _recordingLabel = _recordedVirtualKeyCodes.isEmpty
          ? 'Waiting for shortcut keys...'
          : 'Recording ${labelForVirtualKeyCodes(_recordedVirtualKeyCodes.toList())}. Press more keys, or click Stop recording.';
    });

    if (_recordedVirtualKeyCodes.length >= 3) {
      _saveRecordedShortcut();
    }
  }

  void _saveRecordedShortcut() {
    final shortcut = customHoldShortcutOption(
      _recordedVirtualKeyCodes.toList(),
    );
    widget.controller.selectShortcutOption(shortcut);
    setState(() {
      _isRecording = false;
      _recordingLabel = 'Recorded ${shortcut.label}.';
      _recordedVirtualKeyCodes.clear();
    });
  }
}

int? _virtualKeyCodeForLogicalKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return 0x11;
  }
  if (key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return 0x10;
  }
  if (key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight) {
    return 0x12;
  }
  if (key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight) {
    return 0x5B;
  }
  if (key == LogicalKeyboardKey.space) return 0x20;
  if (key == LogicalKeyboardKey.enter) return 0x0D;
  if (key == LogicalKeyboardKey.tab) return 0x09;
  if (key == LogicalKeyboardKey.escape) return 0x1B;
  if (key == LogicalKeyboardKey.backspace) return 0x08;
  if (key == LogicalKeyboardKey.delete) return 0x2E;
  if (key == LogicalKeyboardKey.arrowLeft) return 0x25;
  if (key == LogicalKeyboardKey.arrowUp) return 0x26;
  if (key == LogicalKeyboardKey.arrowRight) return 0x27;
  if (key == LogicalKeyboardKey.arrowDown) return 0x28;

  final keyLabel = key.keyLabel.toUpperCase();
  if (keyLabel.length == 1) {
    final codeUnit = keyLabel.codeUnitAt(0);
    if ((codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A)) {
      return codeUnit;
    }
  }

  if (key == LogicalKeyboardKey.f1) return 0x70;
  if (key == LogicalKeyboardKey.f2) return 0x71;
  if (key == LogicalKeyboardKey.f3) return 0x72;
  if (key == LogicalKeyboardKey.f4) return 0x73;
  if (key == LogicalKeyboardKey.f5) return 0x74;
  if (key == LogicalKeyboardKey.f6) return 0x75;
  if (key == LogicalKeyboardKey.f7) return 0x76;
  if (key == LogicalKeyboardKey.f8) return 0x77;
  if (key == LogicalKeyboardKey.f9) return 0x78;
  if (key == LogicalKeyboardKey.f10) return 0x79;
  if (key == LogicalKeyboardKey.f11) return 0x7A;
  if (key == LogicalKeyboardKey.f12) return 0x7B;
  return null;
}

class _SpeechSettingsPanel extends StatelessWidget {
  const _SpeechSettingsPanel({required this.controller});

  final SpeechSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Speech recognition', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: controller.languageCode,
              decoration: const InputDecoration(labelText: 'Language'),
              items: [
                for (final language in speechLanguageOptions)
                  DropdownMenuItem(
                    value: language.code,
                    child: Text(language.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.selectLanguage(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MicrophoneSelectionPanel extends StatelessWidget {
  const _MicrophoneSelectionPanel({required this.controller});

  final MicrophoneSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedMicrophone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Microphone', style: theme.textTheme.titleMedium),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isLoading
                      ? null
                      : controller.loadMicrophones,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    controller.isLoading
                        ? 'Scanning...'
                        : 'Refresh microphones',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.hasError)
              Text(
                controller.statusMessage,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else
              Text(controller.statusMessage),
            if (controller.microphones.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<MicrophoneDevice>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Input device'),
                items: [
                  for (final microphone in controller.microphones)
                    DropdownMenuItem(
                      value: microphone,
                      child: Text(microphone.name),
                    ),
                ],
                onChanged: (microphone) {
                  if (microphone != null) {
                    controller.selectMicrophone(microphone);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});

  final DictationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(
                _formatTime(entry.createdAt),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: SelectableText(
                entry.text,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Copy transcription',
              onPressed: () => _copyToClipboard(context),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transcription copied')));
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.mic_none, size: 40),
            SizedBox(height: 12),
            Text('No speech history yet.'),
            SizedBox(height: 4),
            Text(
              'Hold the shortcut, speak, and your generated text will appear here.',
            ),
          ],
        ),
      ),
    );
  }
}
