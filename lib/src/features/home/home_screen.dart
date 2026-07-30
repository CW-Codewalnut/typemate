import 'package:flutter/material.dart';

import '../../core/diagnostics/telemetry_controller.dart';
import '../../core/dictation_controller.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/speech_settings_controller.dart';
import '../../core/stt/stt_model_provisioner.dart';
import '../dictation/dictation_page.dart';
import '../history/history_page.dart';
import '../insights/insights_page.dart';
import '../settings/settings_page.dart';

const double mobileNavigationBreakpoint = 700;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.historyController,
    required this.microphoneController,
    required this.speechSettingsController,
    this.shortcutController,
    this.telemetryController,
    this.logsDirectoryPath,
    this.onQuitRequested,
    this.showDictationTab = false,
    this.modelProvisioner,
    this.microphonePermissionWarmUp,
    this.languageOptions = speechLanguageOptions,
    this.showNoiseSuppression = true,
  });

  final DictationController controller;
  final DictationHistoryController historyController;
  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;
  final TelemetryController? telemetryController;
  final String? logsDirectoryPath;
  final Future<void> Function()? onQuitRequested;

  /// Mobile: dictation runs from an in-app hold-to-talk tab instead of a
  /// global shortcut.
  final bool showDictationTab;

  /// First-run speech model download state for the dictation tab.
  final SttModelProvisioner? modelProvisioner;

  /// Pre-shows the OS microphone permission prompt on the dictation tab.
  final Future<void> Function()? microphonePermissionWarmUp;

  /// Languages this platform's engines serve.
  final List<SpeechLanguageOption> languageOptions;

  final bool showNoiseSuppression;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // With a dictation tab the engine prepares from there, after the model
    // provisioner confirms the files exist (fresh installs have none yet).
    if (!widget.showDictationTab) {
      widget.controller.prepare();
    }
    widget.microphoneController.loadMicrophones();
    widget.historyController.load();
    widget.speechSettingsController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.historyController,
        widget.microphoneController,
        widget.speechSettingsController,
        if (widget.shortcutController != null) widget.shortcutController!,
      ]),
      builder: (context, _) {
        final pages = [
          if (widget.showDictationTab)
            DictationPage(
              controller: widget.controller,
              modelProvisioner: widget.modelProvisioner,
              microphonePermissionWarmUp: widget.microphonePermissionWarmUp,
            ),
          HistoryPage(
            historyController: widget.historyController,
            dictationController: widget.controller,
            shortcutController: widget.shortcutController,
          ),
          InsightsPage(historyController: widget.historyController),
          SettingsPage(
            microphoneController: widget.microphoneController,
            speechSettingsController: widget.speechSettingsController,
            shortcutController: widget.shortcutController,
            telemetryController: widget.telemetryController,
            logsDirectoryPath: widget.logsDirectoryPath,
            onQuitRequested: widget.onQuitRequested,
            languageOptions: widget.languageOptions,
            showNoiseSuppression: widget.showNoiseSuppression,
          ),
        ];
        final page = pages[_selectedIndex.clamp(0, pages.length - 1)];

        return LayoutBuilder(
          builder: (context, constraints) {
            final useBottomNavigation =
                constraints.maxWidth < mobileNavigationBreakpoint;
            return Scaffold(
              body: SafeArea(
                child: useBottomNavigation
                    ? page
                    : Row(
                        children: [
                          NavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: _selectDestination,
                            labelType: NavigationRailLabelType.all,
                            destinations: [
                              for (final destination in _destinations(
                                widget.showDictationTab,
                              ))
                                NavigationRailDestination(
                                  icon: destination.icon,
                                  selectedIcon: destination.selectedIcon,
                                  label: Text(destination.label),
                                ),
                            ],
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: page),
                        ],
                      ),
              ),
              bottomNavigationBar: useBottomNavigation
                  ? NavigationBar(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectDestination,
                      destinations: [
                        for (final destination in _destinations(
                          widget.showDictationTab,
                        ))
                          NavigationDestination(
                            icon: destination.icon,
                            selectedIcon: destination.selectedIcon,
                            label: destination.label,
                          ),
                      ],
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Icon icon;
  final Icon selectedIcon;
  final String label;
}

List<_Destination> _destinations(bool showDictationTab) => [
  if (showDictationTab)
    const _Destination(
      icon: Icon(Icons.mic_none),
      selectedIcon: Icon(Icons.mic),
      label: 'Dictate',
    ),
  const _Destination(
    icon: Icon(Icons.history),
    selectedIcon: Icon(Icons.history_toggle_off),
    label: 'History',
  ),
  const _Destination(
    icon: Icon(Icons.insights_outlined),
    selectedIcon: Icon(Icons.insights),
    label: 'Insights',
  ),
  const _Destination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: 'Settings',
  ),
];
