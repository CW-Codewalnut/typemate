import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaptionButton;

import '../models/app_identity.dart';
import 'window_caption_button.dart';

/// The app's title bar, drawn by Flutter so every desktop OS shows the same
/// light bar: logo on the left, centred title, minimize/maximize/close on
/// the right. The native title bar is hidden at startup (see main.dart);
/// this widget replaces it identically on Windows and Linux instead of
/// per-OS native styling that can drift. All colours derive from the theme.
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key});

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
                          const SizedBox(width: 12),
                          Image.asset(
                            'assets/typemate_icon_1024.png',
                            width: 18,
                            height: 18,
                            filterQuality: FilterQuality.medium,
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
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
            ),
          ],
        ),
      ),
    );
  }
}
