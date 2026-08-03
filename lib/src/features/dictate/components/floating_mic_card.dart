import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/android/floating_mic_controller.dart';

/// Invites the user to turn on the floating mic when it is off. An
/// accessibility service can only be enabled by the user in system
/// settings, so this card is the app's one job: explain it and open the
/// right settings screen. It hides itself once the service is on.
class FloatingMicCard extends StatelessWidget {
  const FloatingMicCard({super.key, required this.controller});

  final FloatingMicController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported || controller.isEnabled) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.record_voice_over_outlined,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dictate in any app',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Turn on the floating mic to dictate straight into any text '
                'field. You enable it once under Accessibility; nothing you '
                'say or type leaves your phone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('enable-floating-mic'),
                  onPressed: () => unawaited(controller.openSettings()),
                  icon: const Icon(Icons.settings_accessibility),
                  label: const Text('Enable floating mic'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
