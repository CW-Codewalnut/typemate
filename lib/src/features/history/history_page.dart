import 'package:flutter/material.dart';

import '../../components/content_page_shell.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import 'components/history_content.dart';

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
      child: HistoryContent(
        historyController: historyController,
        shortcutController: shortcutController,
      ),
    );
  }
}
