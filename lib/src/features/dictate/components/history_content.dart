import 'package:flutter/material.dart';

import '../../../core/dictation_controller.dart';
import '../../../core/dictation_history_controller.dart';
import '../../../core/hold_shortcut_controller.dart';
import '../../../models/dictation_state.dart';
import 'empty_history_card.dart';
import 'history_entry_card.dart';
import 'shortcut_instruction_card.dart';

class HistoryContent extends StatelessWidget {
  const HistoryContent({
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

  /// Replaces the shortcut instruction card. Mobile puts its hold-to-talk
  /// mic in this slot; desktop puts its model-download-aware instruction
  /// card there. Both platforms share one page: how-to-dictate on top,
  /// history below.
  final Widget? dictationSurface;

  /// Whether [dictationSurface] is the mobile hold-to-talk mic, which
  /// words the empty-history hint around the mic instead of the desktop
  /// shortcut.
  final bool mobileSurface;

  /// Mobile titles the page after its tab ("Dictate").
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('history-main-column'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (dictationSurface != null)
          dictationSurface!
        else if (dictationController?.phase == DictationPhase.preparing)
          const ShortcutInstructionCard(
            instruction: 'Starting the speech engine… one moment.',
            busy: true,
          )
        else
          ShortcutInstructionCard(
            instruction: shortcutInstruction(shortcutController),
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
          EmptyHistoryCard(
            hint: mobileSurface
                ? 'Hold the mic above or the floating mic in any app, and '
                      'your dictations will appear here.'
                : dictationSurface != null
                ? 'Hold the mic above or the shortcut in any app, and '
                      'your generated text will appear here.'
                : 'Hold the shortcut, speak, and your generated text will '
                      'appear here.',
          )
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
              onDelete: () => historyController.removeEntry(entry),
              expiresAt: entry.isFailed
                  ? historyController.failedEntryExpiry(entry)
                  : null,
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

/// The hold-to-dictate how-to line, with the user's configured shortcut
/// once known. Shared with the desktop dictation surface so both render
/// the identical instruction.
String shortcutInstruction(HoldShortcutController? shortcutController) {
  final shortcut = shortcutController?.shortcut;
  if (shortcut == null) {
    return 'Press and hold your shortcut and start speaking.';
  }
  return 'Press and hold ${shortcut.label} and start speaking.';
}
