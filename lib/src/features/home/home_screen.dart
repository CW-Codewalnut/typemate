import 'package:flutter/material.dart';

import '../../core/diagnostics/telemetry_controller.dart';
import '../../core/dictation_controller.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/platform/android/floating_mic_controller.dart';
import '../../core/speech_settings_controller.dart';
import '../../core/stt/stt_model_provisioner.dart';
import '../dictate/components/dictation_card.dart';
import '../dictate/dictate_page.dart';
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

  /// Selects the mobile flavor of the shared Dictate surface (floating
  /// mic invitation, permission warm-up, lazy engine load) over the
  /// desktop one (shortcut card, eager engine warm-up).
  final bool useMobileDictationSurface;

  /// Speech model download state: the mobile mic card's first-run
  /// download, and the desktop on-demand download for unbundled models.
  final SpeechModelProvisioner? modelProvisioner;

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
    // Engine preparation is owned by the DictationCard on every platform:
    // it waits for the model provisioner (fresh installs have no model
    // yet), then warms the engine (desktop) or marks ready (mobile).
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
        if (widget.modelProvisioner != null) widget.modelProvisioner!,
      ]),
      builder: (context, _) {
        final pages = [
          DictatePage(
            historyController: widget.historyController,
            dictationController: widget.controller,
            shortcutController: widget.shortcutController,
            // One page on every platform: the dictation surface on top
            // (mic tile, model download, platform capability card), the
            // history of dictations below.
            title: 'Dictate',
            dictationSurface: DictationCard(
              controller: widget.controller,
              modelProvisioner: widget.modelProvisioner,
              microphonePermissionWarmUp: widget.microphonePermissionWarmUp,
              floatingMicController: widget.floatingMicController,
              shortcutController: widget.useMobileDictationSurface
                  ? null
                  : widget.shortcutController,
              desktop: !widget.useMobileDictationSurface,
            ),
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
            // The hold-to-talk mic floats bottom-right on the Dictate tab
            // once the selected language's model exists (until then the
            // page shows the download card instead).
            final modelReady =
                widget.modelProvisioner == null ||
                widget.modelProvisioner!.isReady;
            return Scaffold(
              floatingActionButton: _selectedIndex == 0 && modelReady
                  // Lifted off the window edge: the corner default sits
                  // too tight against the frame for a hold target.
                  ? Padding(
                      padding: const EdgeInsets.only(right: 20, bottom: 20),
                      child: HoldToTalkMicButton(controller: widget.controller),
                    )
                  : null,
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
                              for (final destination in _destinations)
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
                        for (final destination in _destinations)
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

const List<_Destination> _destinations = [
  // One first tab on every platform: the dictation surface plus history,
  // named for what you do there.
  _Destination(
    icon: Icon(Icons.mic_none),
    selectedIcon: Icon(Icons.mic),
    label: 'Dictate',
  ),
  _Destination(
    icon: Icon(Icons.insights_outlined),
    selectedIcon: Icon(Icons.insights),
    label: 'Insights',
  ),
  _Destination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: 'Settings',
  ),
];
