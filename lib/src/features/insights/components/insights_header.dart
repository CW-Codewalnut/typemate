import 'package:flutter/material.dart';

class InsightsHeader extends StatelessWidget {
  const InsightsHeader({super.key, required this.dictationCount});

  final int dictationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Insights',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        _LocalHistoryBadge(entryCount: dictationCount),
      ],
    );
  }
}

class InsightsTabs extends StatelessWidget {
  const InsightsTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(children: [_InsightTab(label: 'Your Usage')]);
  }
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

class _InsightTab extends StatelessWidget {
  const _InsightTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 2, width: 74, color: theme.colorScheme.onSurface),
        ],
      ),
    );
  }
}
