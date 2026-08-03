import 'package:flutter/material.dart';

import '../core/stt/stt_model_provisioner.dart';

/// The speech model download surface, in the instruction-card visual
/// language shared by the desktop shortcut card and the mobile mic tile:
/// checking spinner, download offer, live progress, or retry on failure.
/// The caller owns what happens after a successful download (typically
/// preparing the engine).
class ModelDownloadCard extends StatelessWidget {
  const ModelDownloadCard({
    super.key,
    required this.provisioner,
    required this.onDownloadRequested,
    required this.downloadOfferText,
  });

  final SpeechModelProvisioner provisioner;
  final Future<void> Function() onDownloadRequested;

  /// The one-time download pitch shown next to the Download button; the
  /// caller words it for its platform and model size.
  final String downloadOfferText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (provisioner.phase) {
      SttModelProvisionPhase.checking => const _MessageTile(
        busy: true,
        text: 'Checking the speech model...',
      ),
      SttModelProvisionPhase.downloading => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Downloading the speech model... '
                      '${(provisioner.progress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: provisioner.progress),
              ),
            ],
          ),
        ),
      ),
      SttModelProvisionPhase.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MessageTile(
            icon: Icons.error_outline,
            text: provisioner.errorMessage ?? 'Download failed.',
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('retry-model-download'),
            onPressed: onDownloadRequested,
            icon: const Icon(Icons.refresh),
            label: const Text('Resume download'),
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MessageTile(icon: Icons.download_outlined, text: downloadOfferText),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('start-model-download'),
            onPressed: onDownloadRequested,
            icon: const Icon(Icons.download),
            label: const Text('Download speech model'),
          ),
        ],
      ),
    };
  }
}

/// One tile in the instruction-card language: leading icon (or spinner),
/// titleSmall text, primary-container fill unless overridden.
class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.text,
    this.icon,
    this.busy = false,
    this.background,
    this.foreground,
  });

  final String text;
  final IconData? icon;
  final bool busy;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            background ??
            theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: theme.colorScheme.primary,
                ),
              )
            else if (icon != null)
              Icon(icon, color: foreground ?? theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
