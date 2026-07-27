import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/dictation_history_controller.dart';
import '../../../utils/text_metrics.dart';

class HistoryEntryCard extends StatelessWidget {
  const HistoryEntryCard({super.key, required this.entry, this.onRetry});

  final DictationHistoryEntry entry;

  /// Retries a failed entry's kept recording; null while a retry cannot
  /// run (another dictation in flight, or no recording kept).
  final Future<void> Function()? onRetry;

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
            final transcript = entry.isFailed
                ? Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          entry.failureReason ?? 'Dictation failed.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  )
                : SelectableText(entry.text, style: theme.textTheme.bodyLarge);
            final copyButton = entry.isFailed
                ? _RetryButton(
                    key: const Key('history-retry-button'),
                    onRetry: entry.recordingPath == null ? null : onRetry,
                  )
                : IconButton(
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

/// Retry with an in-place progress spinner while transcription runs.
class _RetryButton extends StatefulWidget {
  const _RetryButton({super.key, required this.onRetry});

  final Future<void> Function()? onRetry;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    if (_retrying) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    final onRetry = widget.onRetry;
    return TextButton.icon(
      onPressed: onRetry == null
          ? null
          : () async {
              setState(() => _retrying = true);
              try {
                await onRetry();
              } finally {
                if (mounted) {
                  setState(() => _retrying = false);
                }
              }
            },
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Retry'),
    );
  }
}
