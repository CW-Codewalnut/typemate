import 'package:flutter/material.dart';

class ContentPageShell extends StatelessWidget {
  const ContentPageShell({
    super.key,
    required this.child,
    this.scrollKey,
    this.maxWidth = 1180,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final Key? scrollKey;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            key: scrollKey,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
