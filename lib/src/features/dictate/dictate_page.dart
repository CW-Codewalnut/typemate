import 'package:flutter/material.dart';

import '../../components/content_page_shell.dart';
import '../../core/dictation_controller.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import 'components/history_content.dart';

class DictatePage extends StatelessWidget {
  const DictatePage({
    super.key,
    required this.historyController,
    this.dictationController,
    this.shortcutController,
    this.dictationSurface,
    this.mobileSurface = false,
    this.title = 'Speech history',
  });

  final DictationHistoryController historyController;
  final DictationController? dictationController;
  final HoldShortcutController? shortcutController;

  /// Replaces the shortcut instruction card: mobile's hold-to-talk mic,
  /// or desktop's model-download-aware instruction card.
  final Widget? dictationSurface;

  /// Whether [dictationSurface] is the mobile mic (words the
  /// empty-history hint accordingly).
  final bool mobileSurface;

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
        mobileSurface: mobileSurface,
        title: title,
      ),
    );
  }
}
