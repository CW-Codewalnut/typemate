import 'package:flutter/material.dart';

/// The one way to render a toggle inside a settings card: rounds the
/// hover/splash ink so it nests cleanly inside the rounded card instead
/// of showing square corners. New settings toggles must use this instead
/// of a raw [SwitchListTile] so the styling cannot drift per panel.
class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.toggleKey,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Applied to the inner [SwitchListTile] so tests can find and read the
  /// actual toggle widget.
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: toggleKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}
