import 'package:flutter/material.dart';

class ListeningOverlayPreview extends StatefulWidget {
  const ListeningOverlayPreview({
    super.key,
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  State<ListeningOverlayPreview> createState() =>
      _ListeningOverlayPreviewState();
}

class _ListeningOverlayPreviewState extends State<ListeningOverlayPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              blurRadius: 24,
              offset: Offset(0, 8),
              color: Color(0x55000000),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 0.35, end: 1).animate(controller),
                child: Icon(widget.icon, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
