import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/hold_shortcut_controller.dart';
import '../utils/virtual_key_codes.dart';

class ShortcutSettingsPanel extends StatefulWidget {
  const ShortcutSettingsPanel({super.key, required this.controller});

  final HoldShortcutController controller;

  @override
  State<ShortcutSettingsPanel> createState() => _ShortcutSettingsPanelState();
}

class _ShortcutSettingsPanelState extends State<ShortcutSettingsPanel> {
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
              _ShortcutStatus(controller: controller),
              const SizedBox(height: 16),
              Text('Current shortcut', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(controller.shortcut.label),
              ),
              const SizedBox(height: 12),
              _ShortcutActions(
                isRecording: _isRecording,
                onToggleRecording: _isRecording
                    ? _stopRecording
                    : _startRecording,
                onReset: controller.resetShortcutToDefault,
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

    unawaited(_saveRecordedShortcut());
  }

  /// Keeps recording (rather than saving) when the capture so far cannot
  /// be a global shortcut, so a lone letter never becomes hold-to-talk.
  bool _rejectRecorded() {
    final reason = holdShortcutRejectionReason(
      _recordedVirtualKeyCodes.toList(),
    );
    if (reason == null) {
      return false;
    }
    setState(() {
      _recordingLabel = reason;
      _recordedVirtualKeyCodes.clear();
    });
    return true;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!_isRecording || event is! KeyDownEvent) {
      return;
    }

    final pressedKeyCodes = HardwareKeyboard.instance.logicalKeysPressed
        .map(virtualKeyCodeForLogicalKey)
        .whereType<int>();
    final eventKeyCode = virtualKeyCodeForLogicalKey(event.logicalKey);
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
      unawaited(_saveRecordedShortcut());
    }
  }

  Future<void> _saveRecordedShortcut() async {
    if (_rejectRecorded()) {
      return;
    }
    final shortcut = customHoldShortcutOption(
      _recordedVirtualKeyCodes.toList(),
    );
    setState(() {
      _isRecording = false;
      _recordingLabel = 'Saving ${shortcut.label}...';
      _recordedVirtualKeyCodes.clear();
    });
    // Awaited: re-registering can fail, and reporting "Recorded X" before
    // it resolves claimed success while the old shortcut was still live.
    await widget.controller.selectShortcutOption(shortcut);
    if (!mounted) {
      return;
    }
    setState(() {
      _recordingLabel = widget.controller.shortcut.id == shortcut.id
          ? 'Recorded ${shortcut.label}.'
          : 'Could not apply ${shortcut.label}. The previous shortcut is '
                'still active.';
    });
  }
}

class _ShortcutStatus extends StatelessWidget {
  const _ShortcutStatus({required this.controller});

  final HoldShortcutController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
    );
  }
}

class _ShortcutActions extends StatelessWidget {
  const _ShortcutActions({
    required this.isRecording,
    required this.onToggleRecording,
    required this.onReset,
  });

  final bool isRecording;
  final VoidCallback onToggleRecording;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: onToggleRecording,
          icon: Icon(isRecording ? Icons.stop_circle_outlined : Icons.keyboard),
          label: Text(isRecording ? 'Stop recording' : 'Record shortcut'),
        ),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset to default'),
        ),
      ],
    );
  }
}
