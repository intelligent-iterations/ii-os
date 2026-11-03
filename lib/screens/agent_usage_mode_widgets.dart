part of 'agent_usage_screen.dart';

/// Interactive versus automated usage, side by side.
///
/// The two answer different questions -- what a person costs at a keyboard, and
/// what the pipelines cost while nobody is watching -- and they are only
/// comparable next to each other.
class _RunModeCard extends StatelessWidget {
  const _RunModeCard({required this.modes});

  final List<AgentModeUsage> modes;

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interactive and automated',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IiOsGap.vXxs,
            Text(
              'Runs someone started at a keyboard, next to runs a pipeline started',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vMd,
            LayoutBuilder(
              builder: (context, constraints) {
                final tiles = [
                  for (final mode in modes) _RunModeTile(usage: mode),
                ];
                if (constraints.maxWidth < IiOsBreakpoints.medium) {
                  return Column(
                    children: [
                      for (final tile in tiles) ...[tile, IiOsGap.vSm],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tile in tiles) ...[
                      Expanded(child: tile),
                      if (tile != tiles.last) IiOsGap.hSm,
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RunModeTile extends StatelessWidget {
  const _RunModeTile({required this.usage});

  final AgentModeUsage usage;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final hue = switch (usage.mode) {
      AgentRunMode.interactive => palette.brand,
      AgentRunMode.automated => palette.info,
      AgentRunMode.unknown => palette.accent,
    };
    return Semantics(
      label: '${usage.mode.label} agent usage',
      child: Container(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        decoration: BoxDecoration(
          color: hue.container,
          borderRadius: IiOsRadii.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              usage.mode.label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: hue.text),
            ),
            IiOsGap.vSm,
            _RunModeRow(label: 'Prompts', value: _number(usage.totals.prompts)),
            _RunModeRow(
              label: 'Sessions',
              value: _number(usage.sessions.sessions),
            ),
            _RunModeRow(
              label: 'Typical session',
              value: _sessionLength(usage.sessions),
            ),
            _RunModeRow(
              label: 'Tokens',
              value: _compact(usage.totals.totalTokens),
            ),
            _RunModeRow(
              label: 'API equivalent',
              value:
                  '\$${usage.totals.apiEquivalentCostUsd.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _RunModeRow extends StatelessWidget {
  const _RunModeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
    child: Row(
      children: [
        // The label yields space so a long value never pushes the row past the
        // tile on a narrow viewport.
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IiOsGap.hXs,
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// A session with one reported event has no measurable span. Saying so beats
/// printing a confident zero.
String _sessionLength(AgentSessionStats stats) {
  if (!stats.hasMeasuredLength) return 'Not measurable';
  return _duration(stats.medianSeconds!);
}

String _duration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}
