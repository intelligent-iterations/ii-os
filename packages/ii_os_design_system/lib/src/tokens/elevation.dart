import 'package:flutter/widgets.dart';

import 'colors.dart';

/// Depth, expressed as tinted shadow rather than a raised grey.
///
/// ii-os previously carried every boundary on a one-pixel hairline, which
/// reads as a wireframe: nothing sits above anything else, so nothing draws
/// the eye. These shadows are tinted with [IiOsColors.ink] rather than pure
/// black, because a neutral-black shadow over a green-leaning canvas turns
/// visibly grey at the edges.
///
/// Each level is two layers on purpose. The tight layer is contact -- it says
/// the surface is resting on something. The wide layer is ambient -- it says
/// how far above. One layer alone reads either as a hard border or as fog.
abstract final class IiOsElevation {
  /// Resting surfaces: cards, list rows, table containers.
  ///
  /// Pair with a hairline border. The shadow separates, the border defines.
  static const List<BoxShadow> low = <BoxShadow>[
    BoxShadow(color: Color(0x0A171B1F), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D171B1F), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Lifted by intent: hover, drag, the selected card in a set.
  static const List<BoxShadow> medium = <BoxShadow>[
    BoxShadow(color: Color(0x0F171B1F), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x14171B1F), blurRadius: 14, offset: Offset(0, 6)),
  ];

  /// Above the page entirely: menus, popovers, dialogs.
  static const List<BoxShadow> high = <BoxShadow>[
    BoxShadow(color: Color(0x14171B1F), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x1F171B1F), blurRadius: 28, offset: Offset(0, 14)),
  ];

  /// A green-tinted glow for the one element currently doing work.
  ///
  /// Reserved for active generation. It is the only shadow that carries a hue
  /// other than ink, which is what makes a running job findable on a page of
  /// resting cards.
  static const List<BoxShadow> working = <BoxShadow>[
    BoxShadow(color: Color(0x1A0B7661), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x260B7661), blurRadius: 18, offset: Offset(0, 4)),
  ];

  /// The levels with the job each one does, for the gallery.
  static const all = <(String, List<BoxShadow>, String)>[
    ('low', low, 'Resting cards, rows, containers'),
    ('medium', medium, 'Hover, drag, selected'),
    ('high', high, 'Menus, popovers, dialogs'),
    ('working', working, 'Active generation only'),
  ];
}
