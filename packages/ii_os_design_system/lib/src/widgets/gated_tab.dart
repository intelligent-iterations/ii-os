import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/palette.dart';
import '../tokens/icons.dart';

/// Whether a tool behind a tab can be used right now.
enum IiOsGateState {
  /// Usable: the tab looks like every other tab.
  open,

  /// Confirmed not usable yet, for example its runtime is not installed.
  locked,

  /// Not known yet, or the source that would say is stale.
  pending,
}

/// A tab whose tool depends on something outside the page.
///
/// A locked or pending tab stays selectable so its page can explain why and
/// how to get unblocked, but it is visibly quieter and carries a badge and a
/// tooltip, so nobody mistakes it for a ready tool. It implements
/// [PreferredSizeWidget] so a [TabBar] sizes it exactly like an icon-and-text
/// [Tab].
class IiOsGatedTab extends StatelessWidget implements PreferredSizeWidget {
  const IiOsGatedTab({
    required this.icon,
    required this.label,
    this.state = IiOsGateState.open,
    this.reason = '',
    super.key,
  });

  final IconData icon;
  final String label;
  final IiOsGateState state;

  /// Why the tool is not usable. Shown as the tooltip and read by assistive
  /// technology; ignored while [state] is [IiOsGateState.open].
  final String reason;

  @override
  Size get preferredSize => Tab(icon: Icon(icon), text: label).preferredSize;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final open = state == IiOsGateState.open;
    final tab = Tab(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 17),
          if (!open)
            Positioned(
              right: -IiOsIconSize.xs / 2,
              top: -IiOsIconSize.xs / 3,
              child: Icon(
                state == IiOsGateState.locked
                    ? LucideIcons.lock
                    : LucideIcons.clock3,
                size: IiOsIconSize.xs * 0.8,
                color: palette.warning.text,
              ),
            ),
        ],
      ),
      child: Text(label),
    );
    if (open) return tab;
    return Tooltip(
      message: reason,
      child: Semantics(
        label: '$label, $reason',
        excludeSemantics: true,
        child: Opacity(opacity: 0.55, child: tab),
      ),
    );
  }
}
