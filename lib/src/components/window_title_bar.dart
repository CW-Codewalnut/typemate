import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// The app's title bar, drawn by Flutter so every desktop OS shows the same
/// light bar: logo on the left, centred title, minimize/maximize/close on
/// the right. The native title bar is hidden at startup (see main.dart);
/// this widget replaces it identically on Windows and Linux instead of
/// per-OS native styling that can drift.
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
    return Material(
      color: Colors.white,
      child: Container(
        height: WindowTitleBar.height,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA))),
        ),
        child: Row(
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
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Type Mate',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2230),
                            ),
                          ),
                        ),
                      ),
                      // Balances the logo so the title stays centred.
                      const SizedBox(width: 30),
                    ],
                  ),
                ),
              ),
            ),
            _WindowButton(
              tooltip: 'Minimize',
              icon: Icons.horizontal_rule,
              onPressed: () async {
                try {
                  await windowManager.minimize();
                } catch (_) {}
              },
            ),
            _WindowButton(
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
              icon: _isMaximized
                  ? Icons.filter_none_outlined
                  : Icons.crop_square,
              iconSize: _isMaximized ? 12 : 14,
              onPressed: _toggleMaximize,
            ),
            _WindowButton(
              tooltip: 'Close',
              icon: Icons.close,
              hoverColor: const Color(0xFFE81123),
              hoverIconColor: Colors.white,
              onPressed: () async {
                try {
                  await windowManager.close();
                } catch (_) {}
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A Windows-style caption button: quiet by default, tinted on hover.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 14,
    this.hoverColor = const Color(0xFFF0F0F4),
    this.hoverIconColor = const Color(0xFF1F2230),
  });

  final String tooltip;
  final IconData icon;
  final double iconSize;
  final Color hoverColor;
  final Color hoverIconColor;
  final VoidCallback onPressed;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: WindowTitleBar.height,
            color: _hovering ? widget.hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovering
                  ? widget.hoverIconColor
                  : const Color(0xFF1F2230),
            ),
          ),
        ),
      ),
    );
  }
}
