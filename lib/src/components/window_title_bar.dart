import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaptionButton;

import '../models/app_identity.dart';
import 'window_caption_button.dart';

/// The app's title bar, drawn by Flutter so every desktop OS shows the same
/// light bar: logo on the left, centred title, minimize/maximize/close on
/// the right. The native title bar is hidden at startup (see main.dart);
/// this widget replaces it identically on Windows and Linux instead of
/// per-OS native styling that can drift. All colours derive from the theme.
///
/// macOS keeps its native traffic lights (hiding the title bar does not
/// remove them), so there the bar shows no Flutter-drawn window buttons and
/// shifts the logo right of the traffic lights.
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key, this.showsCaptionButtons});

  /// Whether to draw minimize/maximize/close. Defaults to every OS except
  /// macOS; tests pass an explicit value so they render the same on any
  /// host.
  final bool? showsCaptionButtons;

  static const double height = 36;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximizedState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = maximized);
      }
    } catch (_) {
      // No window plugin (tests); keep the default state.
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final showsCaptionButtons = widget.showsCaptionButtons ?? !Platform.isMacOS;
    return Material(
      color: colorScheme.surface,
      child: Container(
        height: WindowTitleBar.height,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Stack(
          children: [
            // The title centres on the full bar width — independent of the
            // logo and window buttons — exactly like a native title bar.
            Center(
              child: Text(
                appDisplayName,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  // The whole non-button area drags the window; double-click
                  // toggles maximize, matching native title bars.
                  child: DragToMoveArea(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: _toggleMaximize,
                      child: Row(
                        children: [
                          // On macOS the native traffic lights occupy the
                          // top-left corner; the logo moves out of their way.
                          SizedBox(width: showsCaptionButtons ? 10 : 78),
                          // The logo asset is tightly cropped (the icon
                          // master carries padding and reads too small).
                          Image.asset(
                            'assets/typemate_logo.png',
                            width: 22,
                            height: 22,
                            filterQuality: FilterQuality.medium,
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showsCaptionButtons) ...[
                  WindowCaptionButton(
                    tooltip: 'Minimize',
                    icon: Icons.horizontal_rule,
                    onPressed: () async {
                      try {
                        await windowManager.minimize();
                      } catch (_) {}
                    },
                  ),
                  WindowCaptionButton(
                    tooltip: _isMaximized ? 'Restore' : 'Maximize',
                    icon: _isMaximized
                        ? Icons.filter_none_outlined
                        : Icons.crop_square,
                    iconSize: _isMaximized ? 12 : 14,
                    onPressed: _toggleMaximize,
                  ),
                  WindowCaptionButton(
                    tooltip: 'Close',
                    icon: Icons.close,
                    hoverColor: colorScheme.error,
                    hoverIconColor: colorScheme.onError,
                    onPressed: () async {
                      try {
                        await windowManager.close();
                      } catch (_) {}
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
