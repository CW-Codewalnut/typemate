import 'package:flutter/material.dart';

import '../../core/diagnostics/telemetry_controller.dart';
import '../../core/dictation_controller.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/platform/android/floating_mic_controller.dart';
import '../../core/speech_settings_controller.dart';
import '../../core/stt/stt_model_provisioner.dart';
import '../history/components/mobile_dictation_card.dart';
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
    this.useMobileDictationSurface = false,
    this.modelProvisioner,
    this.microphonePermissionWarmUp,
    this.floatingMicController,
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

  /// Mobile: the first tab is Dictate — the history page with a
  /// hold-to-talk mic card where desktop shows its shortcut instruction.
  final bool useMobileDictationSurface;

  /// First-run speech model download state for the mobile mic card.
  final SttModelProvisioner? modelProvisioner;

  /// Pre-shows the OS microphone permission prompt once dictation
  /// becomes possible.
  final Future<void> Function()? microphonePermissionWarmUp;

  /// Floating-mic enablement state for the mobile dictation card.
  final FloatingMicController? floatingMicController;

  /// Languages this platform's engines serve.
  final List<SpeechLanguageOption> languageOptions;

  final bool showNoiseSuppression;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // On mobile the mic card prepares the engine itself, after the model
    // provisioner confirms the files exist (fresh installs have none yet).
    if (!widget.useMobileDictationSurface) {
      widget.controller.prepare();
    }
    widget.microphoneController.loadMicrophones();
    widget.historyController.load();
    widget.speechSettingsController.load();
    // The floating mic (a separate engine in the same process) appends to
    // the history file while the app is backgrounded; reload on return so
    // those dictations show up.
    _lifecycleListener = AppLifecycleListener(
      onResume: widget.historyController.load,
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
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
          HistoryPage(
            historyController: widget.historyController,
            dictationController: widget.controller,
            shortcutController: widget.shortcutController,
            // Mobile: the same page desktop has, but the instruction slot
            // holds the hold-to-talk mic and the tab is called Dictate.
            title: widget.useMobileDictationSurface
                ? 'Dictate'
                : 'Speech history',
            dictationSurface: widget.useMobileDictationSurface
                ? MobileDictationCard(
                    controller: widget.controller,
                    modelProvisioner: widget.modelProvisioner,
                    microphonePermissionWarmUp:
                        widget.microphonePermissionWarmUp,
                    floatingMicController: widget.floatingMicController,
                  )
                : null,
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
                                widget.useMobileDictationSurface,
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
                          widget.useMobileDictationSurface,
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

List<_Destination> _destinations(bool useMobileDictationSurface) => [
  // One first tab on every platform: dictation how-to plus history. On
  // mobile it leads with the mic, so it is named for what you do there.
  if (useMobileDictationSurface)
    const _Destination(
      icon: Icon(Icons.mic_none),
      selectedIcon: Icon(Icons.mic),
      label: 'Dictate',
    )
  else
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
