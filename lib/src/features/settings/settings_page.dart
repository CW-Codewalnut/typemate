import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/content_page_shell.dart';
import '../../core/hold_shortcut_controller.dart';
import '../../models/app_identity.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/speech_settings_controller.dart';
import 'components/microphone_selection_panel.dart';
import 'components/noise_suppression_panel.dart';
import 'components/shortcut_settings_panel.dart';
import 'components/speech_settings_panel.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.microphoneController,
    required this.speechSettingsController,
    this.shortcutController,
    this.onQuitRequested,
  });

  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;

  /// Shuts the app down completely (closing the window only hides it —
  /// the hotkey keeps working in the background).
  final Future<void> Function()? onQuitRequested;

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
          const SizedBox(height: 24),
          NoiseSuppressionPanel(controller: speechSettingsController),
          if (shortcutController != null) ...[
            const SizedBox(height: 24),
            ShortcutSettingsPanel(controller: shortcutController!),
          ],
          if (onQuitRequested != null) ...[
            const SizedBox(height: 24),
            _QuitPanel(onQuitRequested: onQuitRequested!),
          ],
          const SizedBox(height: 24),
          const _VersionLabel(),
        ],
      ),
    );
  }
}

/// Quit is a Settings action because closing the window only hides it;
/// this is the one place that fully stops the resident speech servers
/// and exits.
class _QuitPanel extends StatelessWidget {
  const _QuitPanel({required this.onQuitRequested});

  final Future<void> Function() onQuitRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Application',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Closing the window keeps TypeMate running so the shortcut '
              'still works. Quit stops it completely.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('quit-typemate'),
              onPressed: onQuitRequested,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: const Text('Quit TypeMate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
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
        final label = info == null
            ? appDisplayName
            : '$appDisplayName v${info.version}';
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
