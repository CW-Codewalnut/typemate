import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                historyController: widget.historyController,
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
                if (widget.controller.phase == DictationPhase.listening ||
                    widget.controller.phase == DictationPhase.transcribing)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: ListeningOverlayPreview(
                        label:
                            widget.controller.phase ==
                                DictationPhase.transcribing
                            ? 'Transcribing'
                            : 'Listening',
                        icon:
                            widget.controller.phase ==
                                DictationPhase.transcribing
                            ? Icons.auto_awesome
                            : Icons.mic,
                      ),
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
    required this.historyController,
    this.shortcutController,
  });

  final DictationHistoryController historyController;
  final HoldShortcutController? shortcutController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ScrollConfiguration(
          key: const Key('history-scrollbar-hidden'),
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final historyContent = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Speech history',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Flexible(
                          child: _ShortcutInstructionCard(
                            instruction: _shortcutInstruction(
                              shortcutController,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (historyController.entries.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      TextButton.icon(
                        onPressed: historyController.clear,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear history'),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (historyController.isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (historyController.entries.isEmpty)
                      const _EmptyHistoryCard()
                    else
                      for (final entry in historyController.entries)
                        _HistoryEntryCard(entry: entry),
                  ],
                );

                final reportCard = _HistoryReportCard(
                  totalWords: historyController.totalWords,
                  wordsPerMinute: historyController.averageWordsPerMinute,
                );

                if (constraints.maxWidth < 780) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      historyContent,
                      const SizedBox(height: 24),
                      reportCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: historyContent),
                    const SizedBox(width: 28),
                    SizedBox(width: 300, child: reportCard),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryReportCard extends StatelessWidget {
  const _HistoryReportCard({
    required this.totalWords,
    required this.wordsPerMinute,
  });

  final int totalWords;
  final int wordsPerMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('history-report-card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HistoryMetricRow(
              value: _formatMetric(totalWords),
              label: 'total words',
            ),
            const SizedBox(height: 18),
            _HistoryMetricRow(value: wordsPerMinute.toString(), label: 'wpm'),
          ],
        ),
      ),
    );
  }

  String _formatMetric(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}

class _HistoryMetricRow extends StatelessWidget {
  const _HistoryMetricRow({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShortcutInstructionCard extends StatelessWidget {
  const _ShortcutInstructionCard({required this.instruction});

  final String instruction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_voice, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                instruction,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortcutInstruction(HoldShortcutController? shortcutController) {
  final shortcut = shortcutController?.shortcut;
  if (shortcut == null) {
    return 'Press and hold your shortcut and start speaking.';
  }
  return 'Press and hold ${shortcut.label} and start speaking.';
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
              _ShortcutSettingsPanel(controller: shortcutController!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShortcutSettingsPanel extends StatefulWidget {
  const _ShortcutSettingsPanel({required this.controller});

  final HoldShortcutController controller;

  @override
  State<_ShortcutSettingsPanel> createState() => _ShortcutSettingsPanelState();
}

class _ShortcutSettingsPanelState extends State<_ShortcutSettingsPanel> {
  final FocusNode _recordFocusNode = FocusNode(debugLabel: 'shortcut-recorder');
  final Set<int> _recordedVirtualKeyCodes = {};
  bool _isRecording = false;
  String _recordingLabel = 'Click record, then press your shortcut.';

  @override
  void dispose() {
    _recordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;

    return KeyboardListener(
      focusNode: _recordFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    controller.isRegistered
                        ? Icons.keyboard_command_key
                        : Icons.keyboard_command_key_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shortcut', style: theme.textTheme.titleMedium),
                        Text(controller.statusMessage),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Current shortcut', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(controller.shortcut.label),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_circle_outlined
                          : Icons.keyboard,
                    ),
                    label: Text(
                      _isRecording ? 'Stop recording' : 'Record shortcut',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.resetShortcutToDefault,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset to default'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isRecording
                    ? _recordingLabel
                    : 'Press up to 3 keys. TypeMate saves automatically at 3 keys, or click Stop recording to save fewer keys.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startRecording() {
    setState(() {
      _recordedVirtualKeyCodes.clear();
      _isRecording = true;
      _recordingLabel = 'Waiting for shortcut keys...';
    });
    _recordFocusNode.requestFocus();
  }

  void _stopRecording() {
    if (_recordedVirtualKeyCodes.isEmpty) {
      setState(() {
        _isRecording = false;
        _recordingLabel = 'No shortcut recorded.';
      });
      return;
    }

    _saveRecordedShortcut();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!_isRecording || event is! KeyDownEvent) {
      return;
    }

    final pressedKeyCodes = HardwareKeyboard.instance.logicalKeysPressed
        .map(_virtualKeyCodeForLogicalKey)
        .whereType<int>();
    final eventKeyCode = _virtualKeyCodeForLogicalKey(event.logicalKey);
    setState(() {
      _recordedVirtualKeyCodes.addAll(pressedKeyCodes);
      if (eventKeyCode != null) {
        _recordedVirtualKeyCodes.add(eventKeyCode);
      }
      _recordingLabel = _recordedVirtualKeyCodes.isEmpty
          ? 'Waiting for shortcut keys...'
          : 'Recording ${labelForVirtualKeyCodes(_recordedVirtualKeyCodes.toList())}. Press more keys, or click Stop recording.';
    });

    if (_recordedVirtualKeyCodes.length >= 3) {
      _saveRecordedShortcut();
    }
  }

  void _saveRecordedShortcut() {
    final shortcut = customHoldShortcutOption(
      _recordedVirtualKeyCodes.toList(),
    );
    widget.controller.selectShortcutOption(shortcut);
    setState(() {
      _isRecording = false;
      _recordingLabel = 'Recorded ${shortcut.label}.';
      _recordedVirtualKeyCodes.clear();
    });
  }
}

int? _virtualKeyCodeForLogicalKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return 0x11;
  }
  if (key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return 0x10;
  }
  if (key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight) {
    return 0x12;
  }
  if (key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight) {
    return 0x5B;
  }
  if (key == LogicalKeyboardKey.space) return 0x20;
  if (key == LogicalKeyboardKey.enter) return 0x0D;
  if (key == LogicalKeyboardKey.tab) return 0x09;
  if (key == LogicalKeyboardKey.escape) return 0x1B;
  if (key == LogicalKeyboardKey.backspace) return 0x08;
  if (key == LogicalKeyboardKey.delete) return 0x2E;
  if (key == LogicalKeyboardKey.arrowLeft) return 0x25;
  if (key == LogicalKeyboardKey.arrowUp) return 0x26;
  if (key == LogicalKeyboardKey.arrowRight) return 0x27;
  if (key == LogicalKeyboardKey.arrowDown) return 0x28;

  final keyLabel = key.keyLabel.toUpperCase();
  if (keyLabel.length == 1) {
    final codeUnit = keyLabel.codeUnitAt(0);
    if ((codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A)) {
      return codeUnit;
    }
  }

  if (key == LogicalKeyboardKey.f1) return 0x70;
  if (key == LogicalKeyboardKey.f2) return 0x71;
  if (key == LogicalKeyboardKey.f3) return 0x72;
  if (key == LogicalKeyboardKey.f4) return 0x73;
  if (key == LogicalKeyboardKey.f5) return 0x74;
  if (key == LogicalKeyboardKey.f6) return 0x75;
  if (key == LogicalKeyboardKey.f7) return 0x76;
  if (key == LogicalKeyboardKey.f8) return 0x77;
  if (key == LogicalKeyboardKey.f9) return 0x78;
  if (key == LogicalKeyboardKey.f10) return 0x79;
  if (key == LogicalKeyboardKey.f11) return 0x7A;
  if (key == LogicalKeyboardKey.f12) return 0x7B;
  return null;
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
            Text('Speech recognition', style: theme.textTheme.titleMedium),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: 'Copy transcription',
              onPressed: () => _copyToClipboard(context),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transcription copied')));
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
