import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/dictation_controller.dart';
import '../../../core/platform/android/floating_mic_controller.dart';
import '../../../core/stt/stt_model_provisioner.dart';
import '../../../models/dictation_state.dart';
import 'floating_mic_card.dart';

/// Mobile's answer to the desktop shortcut instruction card, speaking the
/// exact same visual language (compact tile, primary-container fill,
/// titleSmall text): hold the tile, speak, release. Until the speech
/// model exists the same slot is the first-run download tile instead.
///
/// Dictation lands in the history list underneath; below the tile, an
/// invitation to enable the floating mic shows until it is on.
class MobileDictationCard extends StatefulWidget {
  const MobileDictationCard({
    super.key,
    required this.controller,
    this.modelProvisioner,
    this.microphonePermissionWarmUp,
    this.floatingMicController,
  });

  final DictationController controller;

  /// First-run speech model download state; null means the model needs no
  /// provisioning (tests with a mock engine).
  final SttModelProvisioner? modelProvisioner;

  /// Shows the OS microphone permission prompt as soon as dictation
  /// becomes possible, so the first hold is not interrupted by it. The
  /// floating mic (accessibility overlay) depends on this too: it cannot
  /// show permission dialogs itself.
  final Future<void> Function()? microphonePermissionWarmUp;

  /// Drives the "enable the floating mic" invitation; null hides it
  /// (tests, desktop).
  final FloatingMicController? floatingMicController;

  @override
  State<MobileDictationCard> createState() => _MobileDictationCardState();
}

class _MobileDictationCardState extends State<MobileDictationCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: preparation notifies the controller, and
    // this card mounts inside an already-building listener of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initSpeechRuntime());
      unawaited(widget.floatingMicController?.refresh());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user enables the floating mic in system settings (another app),
    // so re-check when they come back.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.floatingMicController?.refresh());
    }
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
  /// appearing mid-recording strands that first dictation. The engine is
  /// NOT loaded here — it loads lazily on the first dictation, so opening
  /// the app is instant with no "Preparing..." flash.
  Future<void> _makeDictationAvailable() async {
    await widget.microphonePermissionWarmUp?.call();
    widget.controller.markReady();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (widget.modelProvisioner != null) widget.modelProvisioner!,
        if (widget.floatingMicController != null) widget.floatingMicController!,
      ]),
      builder: (context, _) {
        final provisioner = widget.modelProvisioner;
        if (provisioner != null && !provisioner.isReady) {
          return _ProvisioningTile(
            provisioner: provisioner,
            onDownloadRequested: _downloadModel,
          );
        }
        // The in-app tile for a quick capture, then the invitation to
        // turn on the system-wide floating mic (hidden once it is on).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HoldToTalkTile(controller: widget.controller),
            if (widget.floatingMicController != null)
              FloatingMicCard(controller: widget.floatingMicController!),
          ],
        );
      },
    );
  }
}

/// The same tile shape and typography as [ShortcutInstructionCard]; the
/// whole tile is the hold-to-talk surface.
class _HoldToTalkTile extends StatelessWidget {
  const _HoldToTalkTile({required this.controller});

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
    // After a failure the status IS the error, so the one tile turns into
    // the error surface instead of stacking the same text twice.
    final hasError = controller.errorMessage != null;

    return Listener(
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
        decoration: BoxDecoration(
          color: switch ((isListening, hasError)) {
            (true, _) => theme.colorScheme.primary,
            (false, true) => theme.colorScheme.errorContainer,
            (false, false) => theme.colorScheme.primaryContainer.withValues(
              alpha: 0.72,
            ),
          },
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWorking)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: theme.colorScheme.primary,
                ),
              )
            else
              Icon(
                hasError && !isListening
                    ? Icons.error_outline
                    : Icons.keyboard_voice,
                color: switch ((isListening, hasError)) {
                  (true, _) => theme.colorScheme.onPrimary,
                  (false, true) => theme.colorScheme.onErrorContainer,
                  (false, false) => theme.colorScheme.primary,
                },
              ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                controller.statusMessage,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: switch ((isListening, hasError)) {
                    (true, _) => theme.colorScheme.onPrimary,
                    (false, true) => theme.colorScheme.onErrorContainer,
                    (false, false) => null,
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First-run model download in the same tile language.
class _ProvisioningTile extends StatelessWidget {
  const _ProvisioningTile({
    required this.provisioner,
    required this.onDownloadRequested,
  });

  final SttModelProvisioner provisioner;
  final Future<void> Function() onDownloadRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (provisioner.phase) {
      SttModelProvisionPhase.checking => const _MessageTile(
        busy: true,
        text: 'Checking the speech model...',
      ),
      SttModelProvisionPhase.downloading => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Downloading the speech model... '
                      '${(provisioner.progress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: provisioner.progress),
              ),
            ],
          ),
        ),
      ),
      SttModelProvisionPhase.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MessageTile(
            icon: Icons.error_outline,
            text: provisioner.errorMessage ?? 'Download failed.',
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('retry-model-download'),
            onPressed: onDownloadRequested,
            icon: const Icon(Icons.refresh),
            label: const Text('Resume download'),
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MessageTile(
            icon: Icons.download_outlined,
            text:
                'Speech is transcribed on this phone and never leaves it. '
                'That needs a one-time model download of about 640 MB; '
                'Wi-Fi is recommended.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('start-model-download'),
            onPressed: onDownloadRequested,
            icon: const Icon(Icons.download),
            label: const Text('Download speech model'),
          ),
        ],
      ),
    };
  }
}

/// One tile in the instruction-card language: leading icon (or spinner),
/// titleSmall text, primary-container fill unless overridden.
class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.text,
    this.icon,
    this.busy = false,
    this.background,
    this.foreground,
  });

  final String text;
  final IconData? icon;
  final bool busy;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            background ??
            theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: theme.colorScheme.primary,
                ),
              )
            else if (icon != null)
              Icon(icon, color: foreground ?? theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
