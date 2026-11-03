import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The ground generated artwork sits on.
///
/// Deep in both modes, so a thumbnail reads the same whichever theme the
/// viewer is in and nothing around it competes with the picture. It is why
/// editing tools are dark, kept as one surface rather than a whole theme --
/// and it doubles as the backdrop for the states where there is no picture
/// yet, so a grid does not flash white between a spinner and a poster.
class IiOsMediaWell extends StatelessWidget {
  const IiOsMediaWell({required this.child, super.key, this.centre = true});

  final Widget child;

  /// Centres the child. Off when the well is holding a picture that should
  /// fill it rather than sit in the middle of it.
  final bool centre;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: IiOsPalette.of(context).mediaWell,
    child: centre ? Center(child: child) : child,
  );
}
