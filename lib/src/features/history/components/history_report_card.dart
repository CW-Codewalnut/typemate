import 'package:flutter/material.dart';

import '../../../utils/text_metrics.dart';

class HistoryReportCard extends StatelessWidget {
  const HistoryReportCard({
    super.key,
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
              value: formatCompactNumber(totalWords),
              label: 'total words',
            ),
            const SizedBox(height: 18),
            _HistoryMetricRow(value: wordsPerMinute.toString(), label: 'wpm'),
          ],
        ),
      ),
    );
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
