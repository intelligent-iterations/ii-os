import 'package:flutter/material.dart';
import '../theme/palette.dart';
import '../tokens/icons.dart';
import '../tokens/spacing.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Marks a tile as chosen in a grid that takes several.
///
/// A border alone is easy to miss against artwork that may itself be bright
/// at the edges, so the tick sits on an opaque disc rather than over the
/// picture.
class IiOsChosenTick extends StatelessWidget {
  const IiOsChosenTick({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.xxs),
      child: Icon(
        LucideIcons.check,
        size: IiOsIconSize.sm,
        color: IiOsPalette.of(context).surface,
      ),
    ),
  );
}
