import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/content_page_shell.dart';
import '../../core/dictation_controller.dart';
import '../../core/stt/stt_model_provisioner.dart';
import '../../models/dictation_state.dart';

/// The mobile dictation surface: hold the microphone button, speak,
/// release — the transcript appears below and lands on the clipboard,
/// ready to paste into any app. This replaces the desktop global shortcut
/// until the Phase 2 keyboard (IME) types directly into other apps.
class DictationPage extends StatefulWidget {
  const DictationPage({
    super.key,
    required this.controller,
    this.modelProvisioner,
    this.microphonePermissionWarmUp,
  });

  final DictationController controller;

  /// First-run speech model download state; null means the model needs no
  /// provisioning (tests with a mock engine).
  final SttModelProvisioner? modelProvisioner;

  /// Shows the OS microphone permission prompt as soon as dictation
  /// becomes possible, so the first hold-to-talk is not interrupted by it.
  final Future<void> Function()? microphonePermissionWarmUp;

  @override
  State<DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<DictationPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: preparation notifies the controller, and this
    // page mounts inside an already-building listener of it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_initSpeechRuntime()),
    );
  }

  /// The engine can only load once the model files exist, so preparation
  /// waits for the provisioner instead of failing on a fresh install.
  Future<void> _initSpeechRuntime() async {
    final provisioner = widget.modelProvisioner;
    if (provisioner == null) {
      await _makeDictationAvailable();
      return;
    }
    await provisioner.refresh();
    if (provisioner.isReady) {
      await _makeDictationAvailable();
    }
  }

  Future<void> _downloadModel() async {
    final provisioner = widget.modelProvisioner;
    if (provisioner == null) {
      return;
    }
    await provisioner.download();
    if (provisioner.isReady) {
      await _makeDictationAvailable();
    }
  }

  /// The permission prompt fires now, not on the first hold: a dialog
  /// appearing mid-recording strands that first dictation.
  Future<void> _makeDictationAvailable() async {
    await widget.microphonePermissionWarmUp?.call();
    await widget.controller.prepare();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (widget.modelProvisioner != null) widget.modelProvisioner!,
      ]),
      builder: (context, _) {
        final provisioner = widget.modelProvisioner;
        return ContentPageShell(
          scrollKey: const Key('dictation-page'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dictate',
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24),
              if (provisioner != null && !provisioner.isReady)
                _ModelProvisioningCard(
                  provisioner: provisioner,
                  onDownloadRequested: _downloadModel,
                )
              else
                _DictationSurface(controller: widget.controller),
            ],
          ),
        );
      },
    );
  }
}

class _ModelProvisioningCard extends StatelessWidget {
  const _ModelProvisioningCard({
    required this.provisioner,
    required this.onDownloadRequested,
  });

  final SttModelProvisioner provisioner;
  final Future<void> Function() onDownloadRequested;

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
            const SizedBox(height: 8),
            Text(
              'TypeMate transcribes on this phone. Nothing you say leaves '
              'it. That needs a one-time model download of about 640 MB, '
              'so Wi-Fi is recommended.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            switch (provisioner.phase) {
              SttModelProvisionPhase.checking => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              ),
              SttModelProvisionPhase.downloading => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: provisioner.progress),
                  const SizedBox(height: 8),
                  Text(
                    'Downloading... '
                    '${(provisioner.progress * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              SttModelProvisionPhase.failed => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provisioner.errorMessage ?? 'Download failed.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('retry-model-download'),
                    onPressed: onDownloadRequested,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Resume download'),
                  ),
                ],
              ),
              _ => FilledButton.icon(
                key: const Key('start-model-download'),
                onPressed: onDownloadRequested,
                icon: const Icon(Icons.download),
                label: const Text('Download speech model'),
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _DictationSurface extends StatelessWidget {
  const _DictationSurface({required this.controller});

  final DictationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = controller.phase;
    final isListening = phase == DictationPhase.listening;
    final isWorking =
        phase == DictationPhase.transcribing ||
        phase == DictationPhase.inserting ||
        phase == DictationPhase.preparing;
    final transcript = controller.latestTranscript;
    final error = controller.errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Listener(
            onPointerDown: (_) {
              if (!controller.isBusy) {
                unawaited(controller.startListening());
              }
            },
            onPointerUp: (_) => unawaited(controller.stopListening()),
            onPointerCancel: (_) => unawaited(controller.stopListening()),
            child: AnimatedContainer(
              key: const Key('hold-to-dictate-button'),
              duration: const Duration(milliseconds: 150),
              width: isListening ? 132 : 120,
              height: isListening ? 132 : 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primaryContainer,
              ),
              child: isWorking
                  ? Padding(
                      padding: const EdgeInsets.all(44),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  : Icon(
                      Icons.mic,
                      size: 52,
                      color: isListening
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onPrimaryContainer,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            controller.statusMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Hold the mic, speak, release.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        if (transcript.isNotEmpty) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Latest transcript',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        key: const Key('copy-latest-transcript'),
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () => unawaited(
                          Clipboard.setData(ClipboardData(text: transcript)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(transcript, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Copied to your clipboard. Paste it anywhere.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
