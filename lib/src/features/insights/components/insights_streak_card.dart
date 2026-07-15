import 'package:flutter/material.dart';

import '../../../core/insights_stats.dart';
import '../../../utils/text_metrics.dart';
import '../../../components/dashboard_cards.dart';

class InsightsStreakCard extends StatelessWidget {
  const InsightsStreakCard({super.key, required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StreakHeader(stats: stats),
          const SizedBox(height: 22),
          StreakGrid(cells: stats.activityCells),
          const SizedBox(height: 16),
          const _StreakLegend(),
        ],
      ),
    );
  }
}

class _StreakHeader extends StatelessWidget {
  const _StreakHeader({required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentStreakLabel = stats.currentStreakDays == 1
        ? '1 day streak'
        : '${stats.currentStreakDays} day streak';
    final longestStreakLabel = stats.longestStreakDays == 1
        ? 'LONGEST STREAK | 1 DAY'
        : 'LONGEST STREAK | ${stats.longestStreakDays} DAYS';

    return Row(
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
    );
  }
}

class StreakGrid extends StatelessWidget {
  const StreakGrid({super.key, required this.cells});

  final List<ActivityCellData> cells;

  @override
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final usableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final labelWidth = usableWidth < 340 ? 24.0 : 28.0;
        final gap = usableWidth < 340 ? 3.0 : 6.0;
        final cellSize =
            ((usableWidth - labelWidth - (activityGridColumns * gap)) /
                    activityGridColumns)
                .clamp(8.0, 15.0);

        return Column(
          key: const Key('insights-streak-grid'),
          children: [
            for (var row = 0; row < labels.length; row++)
              Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(
                        labels[row],
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    for (
                      var column = 0;
                      column < activityGridColumns;
                      column++
                    ) ...[
                      _StreakCell(
                        cell: cells[row * activityGridColumns + column],
                        size: cellSize,
                      ),
                      SizedBox(width: gap),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StreakCell extends StatelessWidget {
  const _StreakCell({required this.cell, required this.size});

  final ActivityCellData cell;
  final double size;

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
          '${formatShortDate(cell.date)}: ${formatCompactNumber(cell.words)} words',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _StreakLegend extends StatelessWidget {
  const _StreakLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('More', style: theme.textTheme.labelMedium),
        for (final color in [
          theme.colorScheme.primary,
          theme.colorScheme.primary.withValues(alpha: 0.65),
          theme.colorScheme.primary.withValues(alpha: 0.35),
        ])
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        Text('Less', style: theme.textTheme.labelMedium),
        Text('Last 12 weeks', style: theme.textTheme.labelMedium),
      ],
    );
  }
}
