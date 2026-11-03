import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/spec_panel.dart';

/// Decision results and the tabs that gate tools on installed runtimes.
class DecisionsSection extends StatelessWidget {
  const DecisionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecPanel(
          title: 'Decision distribution',
          caption:
              'A probability per option in the order the person wrote them. '
              'The chosen option is carried by weight and the word "chosen" '
              'for assistive technology, not by colour alone.',
          children: [
            IiOsDecisionDistribution(
              shares: [
                IiOsDecisionShare(
                  label: 'angry',
                  probability: 0.8,
                  chosen: true,
                ),
                IiOsDecisionShare(label: 'calm', probability: 0.15),
                IiOsDecisionShare(label: 'excited', probability: 0.05),
              ],
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Gated tab',
          caption:
              'A tool that depends on something outside the page stays '
              'selectable so its page can explain why, but reads as not ready '
              'until it is: quieter, badged, and named in its tooltip.',
          children: [_GatedTabs()],
        ),
      ],
    );
  }
}

class _GatedTabs extends StatelessWidget {
  const _GatedTabs();

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          IiOsGatedTab(icon: LucideIcons.listChecks, label: 'Ready'),
          IiOsGatedTab(
            icon: LucideIcons.listChecks,
            label: 'Not installed',
            state: IiOsGateState.locked,
            reason: 'Runtime not installed',
          ),
          IiOsGatedTab(
            icon: LucideIcons.listChecks,
            label: 'Checking',
            state: IiOsGateState.pending,
            reason: 'Runtime status not confirmed yet',
          ),
        ],
      ),
    );
  }
}
