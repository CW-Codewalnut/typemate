import 'package:flutter/material.dart';

import '../../components/content_page_shell.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import 'components/history_content.dart';
import 'components/history_report_card.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.historyController,
    this.shortcutController,
  });

  final DictationHistoryController historyController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    return ContentPageShell(
      scrollKey: const Key('history-scrollbar-hidden'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final historyContent = HistoryContent(
            historyController: historyController,
            shortcutController: shortcutController,
          );
          final reportCard = SizedBox(
            key: const Key('history-stats-rail'),
            width: 300,
            child: HistoryReportCard(
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
    );
  }
}
