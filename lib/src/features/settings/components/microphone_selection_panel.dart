import 'package:flutter/material.dart';

import '../../../core/audio/ffmpeg_microphone_discovery.dart';
import '../../../core/microphone_settings_controller.dart';

class MicrophoneSelectionPanel extends StatelessWidget {
  const MicrophoneSelectionPanel({super.key, required this.controller});

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
