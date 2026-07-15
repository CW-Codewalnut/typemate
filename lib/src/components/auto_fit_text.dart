import 'package:flutter/material.dart';

/// Single-line text that scales down to fit the available width instead of
/// truncating with an ellipsis, so labels stay readable at narrow widths.
class AutoFitText extends StatelessWidget {
  const AutoFitText(
    this.text, {
    super.key,
    this.style,
    this.alignment = Alignment.centerLeft,
    this.textKey,
  });

  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(text, key: textKey, maxLines: 1, style: style),
    );
  }
}
