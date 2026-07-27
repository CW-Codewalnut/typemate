import 'package:flutter/material.dart';

import '../../../core/dictation_controller.dart';
import '../../../core/dictation_history_controller.dart';
import '../../../core/hold_shortcut_controller.dart';
import 'empty_history_card.dart';
import 'history_entry_card.dart';
import 'shortcut_instruction_card.dart';

class HistoryContent extends StatelessWidget {
  const HistoryContent({
    super.key,
    required this.historyController,
    this.dictationController,
    this.shortcutController,
  });

  final DictationHistoryController historyController;
  final DictationController? dictationController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('history-main-column'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Speech history',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        ShortcutInstructionCard(
          instruction: _shortcutInstruction(shortcutController),
        ),
        if (historyController.entries.isNotEmpty) ...[
          const SizedBox(height: 34),
          _TodayHeader(onClearHistory: historyController.clear),
          const SizedBox(height: 6),
        ],
        if (historyController.entries.isEmpty) const SizedBox(height: 28),
        if (historyController.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (historyController.entries.isEmpty)
          const EmptyHistoryCard()
        else
          for (final entry in historyController.entries)
            HistoryEntryCard(
              entry: entry,
              // One transcription at a time: while any dictation or retry
              // is running, every retry renders disabled (the page
              // rebuilds on controller changes, so they re-enable).
              onRetry:
                  dictationController == null ||
                      entry.recordingPath == null ||
                      dictationController!.isBusy
                  ? null
                  : () => _retryEntry(entry),
            ),
      ],
    );
  }

  /// Retry glue: re-transcribe the kept recording, then either resolve the
  /// failed entry into a transcript or refresh its failure reason.
  Future<void> _retryEntry(DictationHistoryEntry entry) async {
    final controller = dictationController;
    final recordingPath = entry.recordingPath;
    if (controller == null || recordingPath == null || controller.isBusy) {
      return;
    }
    final transcript = await controller.retryTranscription(
      recordingPath,
      duration: entry.duration,
    );
    if (transcript == null) {
      await historyController.updateFailureReason(
        entry,
        controller.errorMessage ??
            DictationController.transcriptionFailedMessage,
      );
      return;
    }
    await historyController.resolveFailedEntry(entry, transcript);
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.onClearHistory});

  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'TODAY',
          key: const Key('history-section-today'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        TextButton.icon(
          onPressed: onClearHistory,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear history'),
        ),
      ],
    );
  }
}

String _shortcutInstruction(HoldShortcutController? shortcutController) {
  final shortcut = shortcutController?.shortcut;
  if (shortcut == null) {
    return 'Press and hold your shortcut and start speaking.';
  }
  return 'Press and hold ${shortcut.label} and start speaking.';
}
