import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/icons.dart';

/// Switches the interface between light and dark.
///
/// Takes the resolved [brightness] rather than the `ThemeMode`, because what
/// the control has to offer is the opposite of what the viewer is looking at --
/// under `ThemeMode.system` the mode alone does not say which that is.
class AppearanceToggle extends StatelessWidget {
  const AppearanceToggle({
    required this.brightness,
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  final Brightness brightness;
  final ValueChanged<Brightness> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final label = dark ? 'Switch to light mode' : 'Switch to dark mode';
    return IconButton(
      key: const Key('appearance-toggle'),
      tooltip: label,
      onPressed: () => onChanged(dark ? Brightness.light : Brightness.dark),
      icon: Icon(
        dark ? LucideIcons.sun : LucideIcons.moon,
        size: compact ? IiOsIconSize.lg : IiOsIconSize.md,
        semanticLabel: label,
      ),
    );
  }
}
