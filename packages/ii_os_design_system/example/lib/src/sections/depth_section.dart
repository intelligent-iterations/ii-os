import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../widgets/spec_panel.dart';

/// Depth, timing, and the one surface allowed to move for its own sake.
///
/// These three belong on one page because they are the same decision seen from
/// different sides: how much attention a thing is asking for. A resting card
/// asks for none, a running generation asks for all of it, and the duration
/// tokens are what stop the difference being improvised per screen.
class DepthSection extends StatelessWidget {
  const DepthSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecPanel(
          title: 'Elevation',
          caption:
              'Two layers per level: a tight contact shadow that says the '
              'surface is resting on something, and a wide ambient one that '
              'says how far above. Tinted with ink rather than black, because '
              'neutral black over a green-leaning canvas reads grey.',
          children: [
            Wrap(
              spacing: IiOsSpacing.md,
              runSpacing: IiOsSpacing.md,
              children: [
                for (final (name, shadow, role) in IiOsElevation.all)
                  _ElevationChip(name: name, shadow: shadow, role: role),
              ],
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Motion',
          caption:
              'Every duration is read through IiOsMotion.of, which returns '
              'zero when the viewer has asked their system for reduced '
              'motion. A hard-coded Duration bypasses that preference, which '
              'is the whole reason these tokens exist.',
          children: [
            for (final (name, duration, role) in IiOsMotion.all)
              Padding(
                padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${duration.inMilliseconds}ms',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        role,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        IiOsGap.vXl,
        const SpecPanel(
          title: 'GenerationSlot',
          caption:
              'The output region in every state it can hold. The execution '
              'boundary requires progress to appear here, in the box the '
              'artifact will occupy, rather than in a toast or a disabled '
              'button. Arrival is allowed a small overshoot because a render '
              'finishing is the payoff of the product; failure only fades.',
          children: [_SlotDemo()],
        ),
      ],
    );
  }
}

class _ElevationChip extends StatelessWidget {
  const _ElevationChip({
    required this.name,
    required this.shadow,
    required this.role,
  });

  final String name;
  final List<BoxShadow> shadow;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(IiOsSpacing.md),
      decoration: BoxDecoration(
        color: IiOsColors.surface,
        borderRadius: IiOsRadii.lgAll,
        border: Border.all(color: IiOsColors.border),
        boxShadow: shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          IiOsGap.vXxs,
          Text(role, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The slot, driven through its states by hand.
///
/// A static screenshot of four boxes would not show the thing worth reviewing,
/// which is the transition between them.
class _SlotDemo extends StatefulWidget {
  const _SlotDemo();

  @override
  State<_SlotDemo> createState() => _SlotDemoState();
}

class _SlotDemoState extends State<_SlotDemo> {
  GenerationPhase _phase = GenerationPhase.idle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: IiOsSpacing.xs,
          children: [
            for (final phase in GenerationPhase.values)
              ChoiceChip(
                label: Text(phase.name),
                selected: _phase == phase,
                onSelected: (_) => setState(() => _phase = phase),
              ),
          ],
        ),
        IiOsGap.vMd,
        SizedBox(
          width: 260,
          child: GenerationSlot(
            phase: _phase,
            workingLabel: 'Generating your image',
            failureMessage: 'The runner never came online.',
            onRetry: () => setState(() => _phase = GenerationPhase.working),
            child: const ColoredBox(
              color: IiOsColors.greenTint,
              child: Center(
                child: Icon(
                  Icons.check_circle_outline,
                  size: 44,
                  color: IiOsColors.green,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
