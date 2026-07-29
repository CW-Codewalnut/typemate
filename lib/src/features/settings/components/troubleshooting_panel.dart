import 'package:flutter/material.dart';

import '../../../components/settings_toggle_tile.dart';
import '../../../core/diagnostics/telemetry_controller.dart';
import '../../../utils/reveal_directory.dart';

/// Diagnostics for bug reports: opens the local error-log folder so the
/// user can attach the file, and holds the anonymous error-reporting
/// consent toggle (shown only in builds with a telemetry backend).
class TroubleshootingPanel extends StatelessWidget {
  const TroubleshootingPanel({
    super.key,
    this.logsDirectoryPath,
    this.telemetryController,
    this.onOpenLogsFolder,
  });

  final String? logsDirectoryPath;
  final TelemetryController? telemetryController;

  /// Injectable for widget tests; defaults to the OS file manager.
  final Future<void> Function(String path)? onOpenLogsFolder;

  bool get _showsTelemetryToggle => telemetryController?.isAvailable ?? false;

  /// Opening the folder can fail (no permissions to create it, no
  /// xdg-open on minimal Linux installs). The troubleshooting button of
  /// all places must not surface an unhandled async error, so failures
  /// land in a snack bar that still shows the path to browse manually.
  Future<void> _openLogsFolder(BuildContext context, String path) async {
    try {
      await (onOpenLogsFolder ?? revealDirectory)(path);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Couldn\'t open the log folder: $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logsPath = logsDirectoryPath;
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
              'Troubleshooting',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'TypeMate keeps a local log of errors to help diagnose '
              'problems. It never contains your voice or dictated text. '
              'Attach the log file when reporting an issue.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (logsPath != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('open-log-folder'),
                onPressed: () => _openLogsFolder(context, logsPath),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Open log folder'),
              ),
            ],
            if (_showsTelemetryToggle) ...[
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: telemetryController!,
                builder: (context, _) => SettingsToggleTile(
                  toggleKey: const Key('telemetry-toggle'),
                  title: const Text('Send anonymous error reports'),
                  subtitle: const Text(
                    'Crash and error reports only. Anonymous, no personal '
                    'data, and never your dictation. Helps fix problems '
                    'faster.',
                  ),
                  value: telemetryController!.enabled,
                  onChanged: (enabled) =>
                      telemetryController!.setEnabled(enabled),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
