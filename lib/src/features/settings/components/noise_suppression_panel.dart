import 'package:flutter/material.dart';

import '../../../components/settings_toggle_tile.dart';
import '../../../core/speech_settings_controller.dart';

/// Card for the optional GTCRN denoising pass that cleans each recording
/// before transcription. Separate from the speech card: it processes the
/// microphone audio and is independent of the selected language.
class NoiseSuppressionPanel extends StatelessWidget {
  const NoiseSuppressionPanel({super.key, required this.controller});

  final SpeechSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Noise suppression', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Cleans steady noise like fans, traffic, and chatter out of '
              'each recording before it is transcribed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SettingsToggleTile(
                toggleKey: const Key('noise-suppression-toggle'),
                title: const Text('Suppress background noise'),
                value: controller.noiseSuppressionEnabled,
                onChanged: (value) =>
                    controller.setNoiseSuppressionEnabled(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
