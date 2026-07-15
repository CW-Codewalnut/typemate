import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/dictation_history_controller.dart';
import '../../../utils/text_metrics.dart';

class HistoryEntryCard extends StatelessWidget {
  const HistoryEntryCard({super.key, required this.entry});

  final DictationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final time = Text(
              formatTimeOfDay(entry.createdAt),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            );
            final transcript = SelectableText(
              entry.text,
              style: theme.textTheme.bodyLarge,
            );
            final copyButton = IconButton(
              tooltip: 'Copy transcription',
              onPressed: () => _copyToClipboard(context),
              icon: const Icon(Icons.copy),
            );

            // On narrow layouts the fixed time column eats too much width,
            // so the time moves above the transcript instead.
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [time, const Spacer(), copyButton]),
                  const SizedBox(height: 4),
                  transcript,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 82, child: time),
                const SizedBox(width: 22),
                Expanded(child: transcript),
                const SizedBox(width: 12),
                copyButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transcription copied')));
  }
}
