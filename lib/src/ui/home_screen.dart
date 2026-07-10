import 'package:flutter/material.dart';

import '../core/dictation_controller.dart';
import '../models/dictation_state.dart';
import 'listening_overlay_preview.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final DictationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                _HomeContent(controller: controller),
                if (controller.phase == DictationPhase.listening)
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

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.controller});

  final DictationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TypeMate',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Local hold to dictate for developers and heavy typers.',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _StatusDot(phase: controller.phase),
                          const SizedBox(width: 12),
                          Text(
                            controller.phase.label,
                            style: theme.textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(controller.statusMessage),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                controller.phase == DictationPhase.preparing
                                ? null
                                : controller.prepare,
                            icon: const Icon(Icons.download_done),
                            label: const Text('Prepare local engine'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                controller.phase ==
                                        DictationPhase.transcribing ||
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
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _InfoPanel(
                      title: 'V1 desktop flow',
                      items: const [
                        'Focus any text field',
                        'Hold a global shortcut',
                        'Speak while the overlay is visible',
                        'Release to transcribe locally',
                        'Insert into the focused field',
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _InfoPanel(
                      title: 'Settings planned',
                      items: const [
                        'Shortcut selection',
                        'Microphone selection',
                        'Default local model setup',
                        'Start at login',
                        'Privacy and local storage controls',
                      ],
                    ),
                  ),
                ],
              ),
              if (controller.latestTranscript.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Latest transcript', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(controller.latestTranscript),
              ],
            ],
          ),
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

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
