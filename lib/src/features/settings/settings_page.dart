import 'package:flutter/material.dart';

import '../../core/hold_shortcut_controller.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/speech_settings_controller.dart';
import 'components/microphone_selection_panel.dart';
import 'components/shortcut_settings_panel.dart';
import 'components/speech_settings_panel.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.microphoneController,
    required this.speechSettingsController,
    this.shortcutController,
  });

  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Text(
              'Settings',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            SpeechSettingsPanel(controller: speechSettingsController),
            const SizedBox(height: 24),
            MicrophoneSelectionPanel(controller: microphoneController),
            if (shortcutController != null) ...[
              const SizedBox(height: 24),
              ShortcutSettingsPanel(controller: shortcutController!),
            ],
          ],
        ),
      ),
    );
  }
}
