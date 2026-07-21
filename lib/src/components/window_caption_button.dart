import 'package:flutter/material.dart';

/// A Windows-style caption button (minimize/maximize/close): quiet by
/// default, tinted on hover. Colours default to the ambient theme; the
/// close button overrides them with the error pair.
class WindowCaptionButton extends StatefulWidget {
  const WindowCaptionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 14,
    this.hoverColor,
    this.hoverIconColor,
  });

  final String tooltip;
  final IconData icon;
  final double iconSize;

  /// Hover background; defaults to the theme hover colour.
  final Color? hoverColor;

  /// Icon colour while hovered; defaults to the theme's onSurface.
  final Color? hoverIconColor;
  final VoidCallback onPressed;

  static const double width = 46;

  @override
  State<WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<WindowCaptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hoverColor = widget.hoverColor ?? Theme.of(context).hoverColor;
    final restingIconColor = colorScheme.onSurface;
    final hoverIconColor = widget.hoverIconColor ?? restingIconColor;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: WindowCaptionButton.width,
            height: double.infinity,
            color: _hovering ? hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovering ? hoverIconColor : restingIconColor,
            ),
          ),
        ),
      ),
    );
  }
}
