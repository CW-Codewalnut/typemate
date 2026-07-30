import 'package:flutter/material.dart';

import '../../components/content_page_shell.dart';
import '../../core/dictation_controller.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import 'components/history_content.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.historyController,
    this.dictationController,
    this.shortcutController,
    this.dictationSurface,
    this.title = 'Speech history',
  });

  final DictationHistoryController historyController;
  final DictationController? dictationController;
  final HoldShortcutController? shortcutController;

  /// Mobile's hold-to-talk mic (and model download), shown where desktop
  /// shows its shortcut instruction card.
  final Widget? dictationSurface;

  final String title;

  @override
  Widget build(BuildContext context) {
    return ContentPageShell(
      scrollKey: const Key('history-scrollbar-hidden'),
      child: HistoryContent(
        historyController: historyController,
        dictationController: dictationController,
        shortcutController: shortcutController,
        dictationSurface: dictationSurface,
        title: title,
      ),
    );
  }
}
