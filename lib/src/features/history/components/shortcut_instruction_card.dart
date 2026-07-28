import 'package:flutter/material.dart';

class ShortcutInstructionCard extends StatelessWidget {
  const ShortcutInstructionCard({
    super.key,
    required this.instruction,
    this.busy = false,
  });

  final String instruction;

  /// Shows a spinner instead of the mic icon while the speech engine is
  /// still starting — the shortcut does nothing during that window, and
  /// silence about it reads as "the app is broken".
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
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
            else
              Icon(Icons.keyboard_voice, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                instruction,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
