import 'package:flutter/material.dart';

import '../../../core/speech_settings_controller.dart';

class SpeechSettingsPanel extends StatelessWidget {
  const SpeechSettingsPanel({
    super.key,
    required this.controller,
    this.options = speechLanguageOptions,
  });

  final SpeechSettingsController controller;

  /// The languages this platform's engines can actually serve; Android
  /// offers the Parakeet subset.
  final List<SpeechLanguageOption> options;

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
                for (final language in options)
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
