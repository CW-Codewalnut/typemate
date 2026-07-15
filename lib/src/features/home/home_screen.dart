import 'package:flutter/material.dart';

import '../../core/dictation_controller.dart';
import '../../core/dictation_history_controller.dart';
import '../../core/hold_shortcut_controller.dart';
import '../../core/microphone_settings_controller.dart';
import '../../core/speech_settings_controller.dart';
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
  });

  final DictationController controller;
  final DictationHistoryController historyController;
  final MicrophoneSettingsController microphoneController;
  final SpeechSettingsController speechSettingsController;
  final HoldShortcutController? shortcutController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.prepare();
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
        final page = switch (_selectedIndex) {
          0 => HistoryPage(
            historyController: widget.historyController,
            shortcutController: widget.shortcutController,
          ),
          1 => InsightsPage(historyController: widget.historyController),
          _ => SettingsPage(
            microphoneController: widget.microphoneController,
            speechSettingsController: widget.speechSettingsController,
            shortcutController: widget.shortcutController,
          ),
        };

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
                            destinations: _railDestinations,
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
                      destinations: _barDestinations,
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

const _railDestinations = [
  NavigationRailDestination(
    icon: Icon(Icons.history),
    selectedIcon: Icon(Icons.history_toggle_off),
    label: Text('History'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.insights_outlined),
    selectedIcon: Icon(Icons.insights),
    label: Text('Insights'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: Text('Settings'),
  ),
];

const _barDestinations = [
  NavigationDestination(
    icon: Icon(Icons.history),
    selectedIcon: Icon(Icons.history_toggle_off),
    label: 'History',
  ),
  NavigationDestination(
    icon: Icon(Icons.insights_outlined),
    selectedIcon: Icon(Icons.insights),
    label: 'Insights',
  ),
  NavigationDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: 'Settings',
  ),
];
