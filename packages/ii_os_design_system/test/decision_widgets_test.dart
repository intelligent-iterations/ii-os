import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _host(Widget child) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: SizedBox(width: 480, child: child)),
);

void main() {
  testWidgets('a distribution names every option and the chosen one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const IiOsDecisionDistribution(
          shares: [
            IiOsDecisionShare(label: 'angry', probability: 0.8, chosen: true),
            IiOsDecisionShare(label: 'calm', probability: 1.4),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('angry, 80%, chosen'), findsOneWidget);
    expect(
      find.bySemanticsLabel('calm, 100%'),
      findsOneWidget,
      reason: 'out-of-range values are clamped, never drawn past the track',
    );
    semantics.dispose();
  });

  testWidgets('a gated tab sizes like a tab and explains a locked tool', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const DefaultTabController(
          length: 2,
          child: TabBar(
            tabs: [
              IiOsGatedTab(icon: LucideIcons.image, label: 'Images'),
              IiOsGatedTab(
                icon: LucideIcons.listChecks,
                label: 'Classify',
                state: IiOsGateState.locked,
                reason: 'Open JEV runtime not installed',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      const IiOsGatedTab(
        icon: LucideIcons.image,
        label: 'Images',
      ).preferredSize.height,
      const Tab(
        icon: Icon(LucideIcons.image),
        text: 'Images',
      ).preferredSize.height,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Classify, Open JEV runtime not installed'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.lock), findsOneWidget);
    expect(find.byTooltip('Open JEV runtime not installed'), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget, reason: 'open tabs are plain');
    semantics.dispose();
  });
}
