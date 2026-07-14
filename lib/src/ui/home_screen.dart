import 'package:flutter/material.dart';

import '../audio/ffmpeg_microphone_discovery.dart';
import '../core/dictation_controller.dart';
import '../core/dictation_history_controller.dart';
import '../core/hold_shortcut_controller.dart';
import '../core/microphone_settings_controller.dart';
import '../core/speech_settings_controller.dart';
import '../models/dictation_state.dart';
import 'listening_overlay_preview.dart';

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
        final page = _selectedIndex == 0
            ? _HistoryPage(
                controller: widget.controller,
                historyController: widget.historyController,
                microphoneController: widget.microphoneController,
                shortcutController: widget.shortcutController,
              )
            : _SettingsPage(
                microphoneController: widget.microphoneController,
                speechSettingsController: widget.speechSettingsController,
                shortcutController: widget.shortcutController,
              );

        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: (index) {
                        setState(() => _selectedIndex = index);
                      },
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.history),
                          selectedIcon: Icon(Icons.history_toggle_off),
                          label: Text('History'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('Settings'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: page),
                  ],
                ),
                if (widget.controller.phase == DictationPhase.listening)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: ListeningOverlayPreview(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({
    required this.controller,
    required this.historyController,
    required this.microphoneController,
    this.shortcutController,
  });

  final DictationController controller;
  final DictationHistoryController historyController;
  final MicrophoneSettingsController microphoneController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canToggleListening =
        microphoneController.selectedMicrophone != null ||
        controller.phase == DictationPhase.listening;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Speech history',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        controller.statusMessage,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _StatusDot(phase: controller.phase),
                const SizedBox(width: 10),
                Text(controller.phase.label),
              ],
            ),
            if (shortcutController != null) ...[
              const SizedBox(height: 16),
              Text(shortcutController!.statusMessage),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      !canToggleListening ||
                          controller.phase == DictationPhase.transcribing ||
                          controller.phase == DictationPhase.inserting
                      ? null
                      : controller.toggleListening,
                  icon: Icon(
                    controller.phase == DictationPhase.listening
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none,
                  ),
                  label: Text(
                    controller.phase == DictationPhase.listening
                        ? 'Release shortcut preview'
                        : 'Hold shortcut preview',
                  ),
                ),
                if (historyController.entries.isNotEmpty)
                  TextButton.icon(
                    onPressed: historyController.clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear history'),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (historyController.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (historyController.entries.isEmpty)
              const _EmptyHistoryCard()
            else
              for (final entry in historyController.entries)
                _HistoryEntryCard(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
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
            _SpeechSettingsPanel(controller: speechSettingsController),
            const SizedBox(height: 24),
            _MicrophoneSelectionPanel(controller: microphoneController),
            if (shortcutController != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            shortcutController!.isRegistered
                                ? Icons.keyboard_command_key
                                : Icons.keyboard_command_key_outlined,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Shortcut',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(shortcutController!.statusMessage),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: shortcutController!.shortcut.id,
                        decoration: const InputDecoration(
                          labelText: 'Hold-to-dictate shortcut',
                        ),
                        items: [
                          for (final shortcut in holdShortcutOptions)
                            DropdownMenuItem(
                              value: shortcut.id,
                              child: Text(shortcut.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            shortcutController!.selectShortcut(value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The shortcut stays active globally while TypeMate is running in the background.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpeechSettingsPanel extends StatelessWidget {
  const _SpeechSettingsPanel({required this.controller});

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
            Text('Speech model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: controller.languageCode,
              decoration: const InputDecoration(labelText: 'Language'),
              items: [
                for (final language in speechLanguageOptions)
                  DropdownMenuItem(
                    value: language.code,
                    child: Text(language.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.selectLanguage(value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: controller.modelId,
              decoration: const InputDecoration(labelText: 'Local model'),
              items: [
                for (final model in controller.availableModels)
                  DropdownMenuItem(value: model.id, child: Text(model.label)),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.selectModel(value);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(controller.selectedModel.description),
          ],
        ),
      ),
    );
  }
}

class _MicrophoneSelectionPanel extends StatelessWidget {
  const _MicrophoneSelectionPanel({required this.controller});

  final MicrophoneSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedMicrophone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Microphone', style: theme.textTheme.titleMedium),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isLoading
                      ? null
                      : controller.loadMicrophones,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    controller.isLoading
                        ? 'Scanning...'
                        : 'Refresh microphones',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.hasError)
              Text(
                controller.statusMessage,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else
              Text(controller.statusMessage),
            if (controller.microphones.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<MicrophoneDevice>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Input device'),
                items: [
                  for (final microphone in controller.microphones)
                    DropdownMenuItem(
                      value: microphone,
                      child: Text(microphone.name),
                    ),
                ],
                onChanged: (microphone) {
                  if (microphone != null) {
                    controller.selectMicrophone(microphone);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});

  final DictationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatTimestamp(entry.createdAt),
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(entry.text, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.mic_none, size: 40),
            SizedBox(height: 12),
            Text('No speech history yet.'),
            SizedBox(height: 4),
            Text(
              'Hold the shortcut, speak, and your generated text will appear here.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.phase});

  final DictationPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = switch (phase) {
      DictationPhase.idle => Colors.green,
      DictationPhase.preparing => Colors.blue,
      DictationPhase.listening => Colors.red,
      DictationPhase.transcribing => Colors.orange,
      DictationPhase.inserting => Colors.purple,
      DictationPhase.error => Colors.redAccent,
    };

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
