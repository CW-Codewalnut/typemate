import 'package:flutter/material.dart';

class EmptyHistoryCard extends StatelessWidget {
  const EmptyHistoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const Key('empty-history-state'),
      width: double.infinity,
      height: 320,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none, size: 44, color: theme.colorScheme.onSurface),
            const SizedBox(height: 14),
            Text('No speech history yet.', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 6),
            Text(
              'Hold the shortcut, speak, and your generated text will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
