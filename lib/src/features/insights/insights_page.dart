import 'package:flutter/material.dart';

import '../../core/dictation_history_controller.dart';
import '../../core/insights_stats.dart';
import '../../components/content_page_shell.dart';
import 'components/insights_activity_card.dart';
import 'components/insights_header.dart';
import 'components/insights_metrics_row.dart';
import 'components/insights_streak_card.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key, required this.historyController});

  final DictationHistoryController historyController;

  @override
  Widget build(BuildContext context) {
    final stats = InsightsStats.fromEntries(historyController.entries);

    return ContentPageShell(
      scrollKey: const Key('insights-page'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InsightsHeader(dictationCount: stats.dictationCount),
          const SizedBox(height: 30),
          InsightsMetricsRow(stats: stats),
          const SizedBox(height: 20),
          _InsightsBottomStack(stats: stats),
        ],
      ),
    );
  }
}

class _InsightsBottomStack extends StatelessWidget {
  const _InsightsBottomStack({required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              InsightsActivityCard(stats: stats),
              const SizedBox(height: 16),
              InsightsStreakCard(stats: stats),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: InsightsActivityCard(stats: stats)),
            const SizedBox(width: 20),
            Expanded(child: InsightsStreakCard(stats: stats)),
          ],
        );
      },
    );
  }
}
