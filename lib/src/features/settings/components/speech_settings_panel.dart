import 'package:flutter/material.dart';

import '../../../core/speech_settings_controller.dart';

class SpeechSettingsPanel extends StatelessWidget {
  const SpeechSettingsPanel({super.key, required this.controller});

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
