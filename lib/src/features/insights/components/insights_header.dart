import 'package:flutter/material.dart';

class InsightsHeader extends StatelessWidget {
  const InsightsHeader({super.key, required this.dictationCount});

  final int dictationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(
          'Insights',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        _LocalHistoryBadge(entryCount: dictationCount),
      ],
    );
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
