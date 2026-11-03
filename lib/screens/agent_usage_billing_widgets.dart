part of 'agent_usage_screen.dart';

class _UsageSummaryCards extends StatelessWidget {
  const _UsageSummaryCards({required this.summary});

  final AgentUsageTotals summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final palette = IiOsPalette.of(context);
      final columns = constraints.maxWidth >= IiOsBreakpoints.expanded
          ? 4
          : constraints.maxWidth >= IiOsBreakpoints.pairedFields
          ? 2
          : 1;
      final width =
          (constraints.maxWidth - (columns - 1) * IiOsSpacing.sm) / columns;
      final cards = [
        KpiCard(
          label: 'Prompts sent',
          value: _number(summary.prompts),
          hue: palette.info,
        ),
        KpiCard(
          label: 'Tokens used',
          value: _compact(summary.totalTokens),
          hue: palette.brand,
        ),
        KpiCard(
          label: 'Cached input',
          value: _compact(summary.cachedInputTokens),
          hue: palette.accent,
        ),
        KpiCard(
          label: 'API-equivalent cost',
          value: '\$${summary.apiEquivalentCostUsd.toStringAsFixed(2)}',
          hue: palette.warning,
        ),
        KpiCard(
          label: 'Actual variable spend',
          value: summary.actualCostUnknownEvents == 0
              ? '\$${summary.actualCostUsd.toStringAsFixed(2)}'
              : '\$${summary.actualCostUsd.toStringAsFixed(2)} known',
          hue: palette.warning,
        ),
      ];
      return Wrap(
        spacing: IiOsSpacing.sm,
        runSpacing: IiOsSpacing.sm,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    },
  );
}

class _ActualCostNotice extends StatelessWidget {
  const _ActualCostNotice({required this.unknownEvents});

  final int unknownEvents;

  @override
  Widget build(BuildContext context) {
    final warning = IiOsPalette.of(context).warning;
    return Container(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      decoration: BoxDecoration(
        color: warning.container,
        border: Border.all(color: warning.text),
        borderRadius: IiOsRadii.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            color: warning.text,
            size: IiOsIconSize.md,
          ),
          IiOsGap.hXs,
          Expanded(
            child: Text(
              '$unknownEvents usage events have no invoice-backed actual '
              'variable cost. Known spend and API-equivalent cost remain '
              'separate.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: warning.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationTable extends StatelessWidget {
  const _AllocationTable({required this.rows});

  final List<AgentUsageAllocation> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.only(top: IiOsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.md),
            child: Text(
              'Jobs, models & billing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IiOsGap.vXs,
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('JOB')),
                    DataColumn(label: Text('MODEL')),
                    DataColumn(label: Text('BILLING')),
                    DataColumn(numeric: true, label: Text('TOKENS')),
                    DataColumn(numeric: true, label: Text('API EQUIV.')),
                    DataColumn(numeric: true, label: Text('ACTUAL VAR.')),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          DataCell(Text(_displayJobName(row.jobName))),
                          DataCell(Text(_displayName(row.model))),
                          DataCell(
                            Text(
                              '${row.billingMode.label}\n'
                              '${_displayName(row.billingProvider)} · '
                              '${_displayName(row.billingPlan)}',
                            ),
                          ),
                          DataCell(Text(_compact(row.totals.totalTokens))),
                          DataCell(
                            Text(
                              '\$${row.totals.apiEquivalentCostUsd.toStringAsFixed(2)}',
                            ),
                          ),
                          DataCell(Text(_actualCost(row.totals))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SubscriptionTable extends StatelessWidget {
  const _SubscriptionTable({required this.rows});

  final List<AgentUsageSubscription> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.only(top: IiOsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.md),
            child: Text(
              'Monthly subscriptions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IiOsGap.vXs,
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('PROVIDER')),
                    DataColumn(label: Text('PLAN')),
                    DataColumn(numeric: true, label: Text('MONTHLY SPEND')),
                    DataColumn(numeric: true, label: Text('TOKENS')),
                    DataColumn(numeric: true, label: Text('API EQUIV.')),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          DataCell(Text(_displayName(row.billingProvider))),
                          DataCell(Text(_displayName(row.billingPlan))),
                          DataCell(
                            Text(
                              row.monthlyCostUsd == null
                                  ? 'Not configured'
                                  : '\$${row.monthlyCostUsd!.toStringAsFixed(2)}',
                            ),
                          ),
                          DataCell(Text(_compact(row.totals.totalTokens))),
                          DataCell(
                            Text(
                              '\$${row.totals.apiEquivalentCostUsd.toStringAsFixed(2)}',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _actualCost(AgentUsageTotals totals) =>
    totals.actualCostUnknownEvents == 0
    ? '\$${totals.actualCostUsd.toStringAsFixed(2)}'
    : '\$${totals.actualCostUsd.toStringAsFixed(2)} known + unknown';

String _displayJobName(String value) => switch (value) {
  'work-ticket' => 'Agent work ticket',
  _ => _displayName(value),
};
