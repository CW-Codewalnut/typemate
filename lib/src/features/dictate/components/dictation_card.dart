import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/model_download_card.dart';
import '../../../core/dictation_controller.dart';
import '../../../core/hold_shortcut_controller.dart';
import '../../../core/platform/android/floating_mic_controller.dart';
import '../../../core/stt/stt_model_provisioner.dart';
import '../../../models/dictation_state.dart';
import 'floating_mic_card.dart';

/// The one dictation surface, identical on every platform: hold the mic
/// tile, speak, release. Until the selected language's speech model exists
/// the same slot is the download tile instead. Below the tile sits the
/// platform's system-wide capability card — the floating mic invitation on
/// mobile, the global-shortcut instruction on desktop.
///
/// Dictation lands in the history list underneath.
class DictationCard extends StatefulWidget {
  const DictationCard({
    super.key,
    required this.controller,
    this.modelProvisioner,
    this.microphonePermissionWarmUp,
    this.floatingMicController,
    this.shortcutController,
    this.desktop = false,
  });

  final DictationController controller;

  /// Speech model download state; null means the model needs no
  /// provisioning (fully bundled install, or tests with a mock engine).
  final SpeechModelProvisioner? modelProvisioner;

  /// Shows the OS microphone permission prompt as soon as dictation
  /// becomes possible, so the first hold is not interrupted by it. The
  /// floating mic (accessibility overlay) depends on this too: it cannot
  /// show permission dialogs itself. Mobile only.
  final Future<void> Function()? microphonePermissionWarmUp;

  /// Drives the "enable the floating mic" invitation; null hides it
  /// (desktop, tests).
  final FloatingMicController? floatingMicController;

  /// Shows the global-shortcut instruction below the tile; null hides it
  /// (mobile, tests).
  final HoldShortcutController? shortcutController;

  /// Desktop behavior: once the model exists the engine loads eagerly so
  /// the resident model is warm before the first hotkey press, and the
  /// download offer is worded for a computer. Mobile (default) marks ready
  /// without loading — the model loads lazily on the first dictation so
  /// opening the app is instant.
  final bool desktop;

  @override
  State<DictationCard> createState() => _DictationCardState();
}

class _DictationCardState extends State<DictationCard>
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
  /// appearing mid-recording strands that first dictation. Desktop then
  /// loads the engine eagerly (a warm resident model keeps the hotkey
  /// loop at ~1s); mobile only marks ready and loads lazily on the first
  /// dictation, so opening the app is instant.
  Future<void> _makeDictationAvailable() async {
    await widget.microphonePermissionWarmUp?.call();
    if (widget.desktop) {
      unawaited(widget.controller.prepare());
    } else {
      widget.controller.markReady();
    }
  }

  /// One quiet line under the tile: the system-wide way to dictate. The
  /// tile itself is the in-app way, so this stays plain text, not a card.
  String get _shortcutHint {
    final label = widget.shortcutController?.shortcut.label;
    return label == null
        ? 'You can also press and hold your shortcut in any app to '
              'dictate there.'
        : 'You can also press and hold $label in any app to dictate there.';
  }

  String _downloadOfferText(SpeechModelProvisioner provisioner) {
    // Rounded to the nearest 10 MB: exact byte counts read as noise.
    final megabytes =
        ((provisioner.expectedTotalBytes / (1024 * 1024)) / 10).round() * 10;
    return widget.desktop
        ? 'Speech is transcribed on this computer and never leaves it. '
              'That needs a one-time model download of about $megabytes MB.'
        : 'Speech is transcribed on this phone and never leaves it. '
              'That needs a one-time model download of about $megabytes MB; '
              'Wi-Fi is recommended.';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (widget.modelProvisioner != null) widget.modelProvisioner!,
        if (widget.floatingMicController != null) widget.floatingMicController!,
        if (widget.shortcutController != null) widget.shortcutController!,
      ]),
      builder: (context, _) {
        final provisioner = widget.modelProvisioner;
        if (provisioner != null && !provisioner.isReady) {
          return ModelDownloadCard(
            provisioner: provisioner,
            onDownloadRequested: _downloadModel,
            downloadOfferText: _downloadOfferText(provisioner),
          );
        }
        // The in-app tile for a quick capture, then the platform's
        // system-wide capability: the floating mic invitation (hidden once
        // it is on) or a quiet one-line reminder of the global shortcut.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HoldToTalkTile(controller: widget.controller),
            if (widget.floatingMicController != null)
              FloatingMicCard(controller: widget.floatingMicController!),
            if (widget.shortcutController != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  _shortcutHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The instruction-card tile shape and typography; the whole tile is the
/// hold-to-talk surface.
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
