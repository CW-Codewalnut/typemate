import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/model_download_card.dart';
import '../../../core/dictation_controller.dart';
import '../../../core/hold_shortcut_controller.dart';
import '../../../core/platform/android/floating_mic_controller.dart';
import '../../../core/stt/stt_model_provisioner.dart';
import '../../../models/dictation_state.dart';
import 'floating_mic_card.dart';
import 'shortcut_instruction_card.dart';

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
        // While the engine loads, the card slot says so with a busy card;
        // it disappears once the engine is ready.
        if (widget.controller.phase == DictationPhase.preparing) {
          return const ShortcutInstructionCard(
            instruction: 'Preparing the speech engine… one moment.',
            busy: true,
          );
        }
        // The platform's system-wide capability: the floating mic
        // invitation (hidden once it is on) or a quiet one-line reminder
        // of the global shortcut. The hold-to-talk mic itself floats
        // bottom-right as the page's FAB and narrates its own state;
        // failures show on the toast and in History.
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.floatingMicController != null)
              FloatingMicCard(controller: widget.floatingMicController!),
            if (widget.shortcutController != null)
              Text(
                _shortcutHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The hold-to-talk mic: a round floating-action-style button, shown
/// bottom-right as the Dictate page's FAB — the same surface on every
/// platform. Press and hold to dictate; while active it expands into a
/// pill with the live state beside the icon ("Listening...",
/// "Transcribing..."), then shrinks back to the idle circle.
class HoldToTalkMicButton extends StatelessWidget {
  const HoldToTalkMicButton({super.key, required this.controller});

  final DictationController controller;

  static const double _diameter = 72;

  /// The label shown beside the icon while dictation is in flight; null
  /// keeps the idle circle.
  String? _activeLabel(DictationPhase phase) => switch (phase) {
    DictationPhase.listening => 'Listening...',
    DictationPhase.transcribing ||
    DictationPhase.inserting => 'Transcribing...',
    DictationPhase.preparing => 'Preparing...',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = controller.phase;
    final isListening = phase == DictationPhase.listening;
    final isWorking =
        phase == DictationPhase.transcribing ||
        phase == DictationPhase.inserting ||
        phase == DictationPhase.preparing;
    final label = _activeLabel(phase);
    // After a failure the button turns into the error surface; the toast
    // and the failed History entry carry the reason.
    final hasError = controller.errorMessage != null;
    final foreground = switch ((isListening, hasError)) {
      (true, _) => theme.colorScheme.onPrimary,
      (false, true) => theme.colorScheme.onErrorContainer,
      (false, false) => theme.colorScheme.primary,
    };

    return Listener(
      onPointerDown: (_) {
        if (!controller.isBusy) {
          unawaited(controller.startListening());
        }
      },
      onPointerUp: (_) => unawaited(controller.stopListening()),
      onPointerCancel: (_) => unawaited(controller.stopListening()),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          key: const Key('hold-to-dictate-button'),
          height: _diameter,
          constraints: const BoxConstraints(minWidth: _diameter),
          padding: label == null
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_diameter / 2),
            color: switch ((isListening, hasError)) {
              (true, _) => theme.colorScheme.primary,
              (false, true) => theme.colorScheme.errorContainer,
              (false, false) => theme.colorScheme.primaryContainer,
            },
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(
                  alpha: isListening ? 0.30 : 0.15,
                ),
                blurRadius: isListening ? 18 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isWorking)
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: foreground,
                  ),
                )
              else
                Icon(
                  hasError && !isListening
                      ? Icons.error_outline
                      : Icons.keyboard_voice,
                  size: 30,
                  color: foreground,
                ),
              if (label != null) ...[
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
