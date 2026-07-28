import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/dictation_history_controller.dart';
import '../../../utils/text_metrics.dart';

class HistoryEntryCard extends StatelessWidget {
  const HistoryEntryCard({
    super.key,
    required this.entry,
    this.onRetry,
    this.onDelete,
    this.expiresAt,
  });

  final DictationHistoryEntry entry;

  /// Retries a failed entry's kept recording; null while a retry cannot
  /// run (another dictation in flight, or no recording kept).
  final Future<void> Function()? onRetry;

  /// Deletes a failed entry (and its kept recording) immediately.
  final Future<void> Function()? onDelete;

  /// When the 30-day sweep will delete this failed entry, shown so the
  /// user knows the recording does not sit around forever.
  final DateTime? expiresAt;

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
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                      ),
                      if (expiresAt case final DateTime expiry) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 26),
                          child: Text(
                            _autoDeleteLabel(expiry),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                : SelectableText(entry.text, style: theme.textTheme.bodyLarge);
            final copyButton = entry.isFailed
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RetryButton(
                        key: const Key('history-retry-button'),
                        onRetry: entry.recordingPath == null ? null : onRetry,
                      ),
                      if (onDelete != null)
                        IconButton(
                          key: const Key('history-delete-button'),
                          tooltip: 'Delete now (also removes the recording)',
                          onPressed: () => onDelete!(),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
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

  /// "Auto-deletes in N days" so the kept recording's lifetime is visible;
  /// counts up (ceiling) so a fresh entry shows the full window.
  String _autoDeleteLabel(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative || remaining.inHours < 24) {
      return 'Auto-deletes today';
    }
    final days = (remaining.inSeconds / Duration.secondsPerDay).ceil();
    return 'Auto-deletes in $days ${days == 1 ? 'day' : 'days'}';
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
