import 'package:flutter/material.dart';

import '../../../core/insights_stats.dart';
import '../../../utils/text_metrics.dart';
import '../../../components/dashboard_cards.dart';

class InsightsActivityCard extends StatelessWidget {
  const InsightsActivityCard({super.key, required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
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

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActivityCardHeader(
            title: 'Dictation activity',
            sessionCount: stats.dictationCount,
          ),
          const SizedBox(height: 18),
          for (final row in rows) _UsageBar(row: row),
        ],
      ),
    );
  }

  int _percent(int value, int total) {
    if (value <= 0 || total <= 0) return 0;
    return ((value / total) * 100).round().clamp(1, 100);
  }
}

class _ActivityCardHeader extends StatelessWidget {
  const _ActivityCardHeader({required this.title, required this.sessionCount});

  final String title;
  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            'TOTAL SESSIONS | $sessionCount',
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
    );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(row.icon, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${formatCompactNumber(row.words)} ${row.label}'
                            .toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: row.percent / 100,
                    minHeight: 22,
                    backgroundColor: theme.colorScheme.surface,
                  ),
                ),
              ],
            ),
          );
        }

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
                  '${formatCompactNumber(row.words)} ${row.label}'
                      .toUpperCase(),
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
      },
    );
  }
}
