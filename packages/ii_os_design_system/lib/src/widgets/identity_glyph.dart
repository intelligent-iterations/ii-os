import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/identity.dart';

/// The icon that says *which one* -- a production line, or anything else an
/// operator navigates between and gives an identity to.
///
/// The colour is set on the [Icon] itself rather than left to the surrounding
/// [IconTheme]. That is deliberate and load-bearing: `ListTile.selectedColor`
/// tints its leading icon through the theme, so a themed glyph would turn the
/// selection colour exactly when the operator is standing in that item and
/// lose the identity it exists to carry. A widget's own colour wins over an
/// inherited one, so this survives selection.
///
/// [needsAttention] draws the amber status dot. That is a *state*, so it uses
/// the warning colour and never the identity hue -- the two must not be
/// confusable at a glance.
class IiOsIdentityGlyph extends StatelessWidget {
  const IiOsIdentityGlyph({
    required this.colorToken,
    required this.iconToken,
    this.size = railSize,
    this.needsAttention = false,
    this.semanticLabel,
    super.key,
  });

  /// Sidebar size: matches the rail's other leading icons.
  static const railSize = 19.0;

  /// Page-header size: reads as a title companion rather than a list marker.
  static const headerSize = 26.0;

  final String? colorToken;
  final String? iconToken;
  final double size;
  final bool needsAttention;

  /// Announced instead of the glyph. Colour and shape carry no meaning to a
  /// screen reader, so the name has to.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      IiOsIdentity.iconFor(iconToken),
      size: size,
      color: IiOsIdentity.colorFor(colorToken),
      semanticLabel: semanticLabel,
    );
    if (!needsAttention) return glyph;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        glyph,
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            width: size / 3,
            height: size / 3,
            decoration: const BoxDecoration(
              color: IiOsColors.amber,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
