import 'package:flutter/material.dart';

class ContentPageShell extends StatelessWidget {
  const ContentPageShell({
    super.key,
    required this.child,
    this.scrollKey,
    this.maxWidth = 1180,
    this.minWidth = 0,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final Key? scrollKey;
  final double maxWidth;
  final double minWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = minWidth > constraints.maxWidth
                ? minWidth
                : constraints.maxWidth;
            return ScrollConfiguration(
              behavior: const _NoScrollbarScrollBehavior(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  child: SingleChildScrollView(
                    key: scrollKey,
                    padding: padding,
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NoScrollbarScrollBehavior extends MaterialScrollBehavior {
  const _NoScrollbarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
