import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/content_page_shell.dart';
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

    return ContentPageShell(
      scrollKey: const Key('settings-page'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 24),
          const _VersionLabel(),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final label = info == null ? 'Type Mate' : 'Type Mate v${info.version}';
        return Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
