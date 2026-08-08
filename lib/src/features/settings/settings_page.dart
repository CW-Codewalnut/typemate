import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/content_page_shell.dart';
import '../../core/diagnostics/telemetry_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import '../../models/app_identity.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/speech_settings_controller.dart';
import 'components/microphone_selection_panel.dart';
import 'components/noise_suppression_panel.dart';
import 'components/shortcut_settings_panel.dart';
import 'components/speech_settings_panel.dart';
import 'components/troubleshooting_panel.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.microphoneController,
    required this.speechSettingsController,
    this.shortcutController,
    this.telemetryController,
    this.logsDirectoryPath,
    this.logFilePath,
    this.onOpenLogsFolder,
    this.onQuitRequested,
    this.languageOptions = speechLanguageOptions,
    this.showNoiseSuppression = true,
    this.showHardwareShortcutNote = false,
  });

  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;

  /// Languages the current platform's engines serve (Android offers the
  /// Parakeet subset only).
  final List<SpeechLanguageOption> languageOptions;

  /// Shown on every platform now that GTCRN runs in-process through the
  /// sherpa_onnx plugin; the flag survives so a platform that cannot run
  /// it can still hide the toggle, because a visible toggle must work.
  final bool showNoiseSuppression;

  /// Anonymous error-reporting consent; null or unavailable hides the
  /// toggle (tests and builds without a telemetry DSN).
  final TelemetryController? telemetryController;

  /// Where the local diagnostic log lives; null hides the whole
  /// Troubleshooting panel (tests without a reporter).
  final String? logsDirectoryPath;

  /// Mobile: the log file offered through the system share sheet instead
  /// of a folder to open.
  final String? logFilePath;

  /// Mobile: describes the fixed physical-keyboard shortcut (Ctrl+Meta,
  /// served by the accessibility service) — informational, since Android
  /// offers no app-configurable global shortcuts.
  final bool showHardwareShortcutNote;

  /// Injectable for widget tests; defaults to the OS file manager.
  final Future<void> Function(String path)? onOpenLogsFolder;

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
          SpeechSettingsPanel(
            controller: speechSettingsController,
            options: languageOptions,
          ),
          const SizedBox(height: 24),
          MicrophoneSelectionPanel(controller: microphoneController),
          if (showNoiseSuppression) ...[
            const SizedBox(height: 24),
            NoiseSuppressionPanel(controller: speechSettingsController),
          ],
          if (shortcutController != null) ...[
            const SizedBox(height: 24),
            ShortcutSettingsPanel(controller: shortcutController!),
          ] else if (showHardwareShortcutNote) ...[
            const SizedBox(height: 24),
            const _HardwareShortcutNote(),
          ],
          if (logsDirectoryPath != null ||
              logFilePath != null ||
              (telemetryController?.isAvailable ?? false)) ...[
            const SizedBox(height: 24),
            TroubleshootingPanel(
              logsDirectoryPath: logsDirectoryPath,
              logFilePath: logFilePath,
              telemetryController: telemetryController,
              onOpenLogsFolder: onOpenLogsFolder,
            ),
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

/// Android's shortcut story, stated honestly: the combo is fixed and
/// served by the accessibility service; the OS offers no app-configurable
/// global shortcuts to record.
class _HardwareShortcutNote extends StatelessWidget {
  const _HardwareShortcutNote();

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
              'Keyboard shortcut',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'With a physical keyboard connected, press and hold Ctrl+Meta '
              'in any app to dictate. Needs the floating mic (accessibility '
              'service) to be on. Android does not allow apps to offer '
              'custom global shortcuts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
