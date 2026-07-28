import 'package:flutter/material.dart';

import '../../../core/audio/microphone_discovery.dart';
import '../../../core/microphone_settings_controller.dart';

/// Card with the input-device dropdown. While it is on screen the
/// controller re-scans on an interval, so plugging in or removing a
/// microphone updates the list without reopening the app.
class MicrophoneSelectionPanel extends StatefulWidget {
  const MicrophoneSelectionPanel({super.key, required this.controller});

  final MicrophoneSettingsController controller;

  @override
  State<MicrophoneSelectionPanel> createState() =>
      _MicrophoneSelectionPanelState();
}

class _MicrophoneSelectionPanelState extends State<MicrophoneSelectionPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.startWatchingDevices();
  }

  @override
  void dispose() {
    widget.controller.stopWatchingDevices();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final selected = controller.selectedMicrophone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Microphone', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (controller.hasError)
              Text(
                controller.statusMessage,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (controller.microphones.isEmpty || controller.isLoading)
              Text(controller.statusMessage),
            if (controller.microphones.isNotEmpty) ...[
              DropdownButtonFormField<MicrophoneDevice>(
                // A FormField caches its initial value, so the field is
                // recreated whenever the device list or selection changes;
                // without this the dropdown keeps showing a list that no
                // longer matches reality.
                key: ValueKey(
                  Object.hashAll([selected, ...controller.microphones]),
                ),
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
