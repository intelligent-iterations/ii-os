part of 'agent_usage_screen.dart';

class _UsageFilters extends StatelessWidget {
  const _UsageFilters({
    required this.days,
    required this.origin,
    required this.onChanged,
  });

  final int days;
  final AgentExecutionOrigin origin;
  final void Function(int days, AgentExecutionOrigin origin) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IiOsSpacing.sm,
      runSpacing: IiOsSpacing.sm,
      children: [
        SizedBox(
          width: IiOsWidths.wideForm / 2,
          child: DropdownButtonFormField<int>(
            key: ValueKey('agent-usage-days-$days'),
            initialValue: days,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Time window',
              prefixIcon: Icon(LucideIcons.calendarDays, size: 18),
            ),
            items: const [
              DropdownMenuItem(value: 7, child: Text('Last 7 days')),
              DropdownMenuItem(value: 30, child: Text('Last 30 days')),
              DropdownMenuItem(value: 90, child: Text('Last 90 days')),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value, origin);
            },
          ),
        ),
        SizedBox(
          width: IiOsWidths.wideForm / 2,
          child: DropdownButtonFormField<AgentExecutionOrigin>(
            key: ValueKey('agent-usage-origin-${origin.value}'),
            initialValue: origin,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ran from',
              prefixIcon: Icon(LucideIcons.cloudCog, size: 18),
            ),
            items: [
              for (final value in AgentExecutionOrigin.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) {
              if (value != null) onChanged(days, value);
            },
          ),
        ),
      ],
    );
  }
}

class _UsageReport extends StatelessWidget {
  const _UsageReport({required this.report});

  final AgentUsageReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UsageSummaryCards(summary: summary),
        if (summary.actualCostUnknownEvents > 0) ...[
          IiOsGap.vSm,
          _ActualCostNotice(unknownEvents: summary.actualCostUnknownEvents),
        ],
        if (!report.coverage.hasTokenTelemetry && summary.prompts > 0) ...[
          IiOsGap.vSm,
          const _CoverageNotice(),
        ],
        IiOsGap.vMd,
        _RunModeCard(modes: report.byMode),
        if (report.byMode.isNotEmpty) IiOsGap.vMd,
        if (report.allocations.isNotEmpty) ...[
          _AllocationTable(rows: report.allocations),
          IiOsGap.vMd,
        ],
        if (report.subscriptions.isNotEmpty) ...[
          _SubscriptionTable(rows: report.subscriptions),
          IiOsGap.vMd,
        ],
        _DailyUsageCard(days: report.days, values: report.daily),
        IiOsGap.vMd,
        _BreakdownTable(
          title: 'Models',
          dimension: 'Model',
          rows: report.byModel,
        ),
        IiOsGap.vMd,
        _UsageDimensionCards(report: report),
      ],
    );
  }
}

class _UsageDimensionCards extends StatelessWidget {
  const _UsageDimensionCards({required this.report});

  final AgentUsageReport report;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cards = [
        _BreakdownTable(
          title: 'Agents',
          dimension: 'Agent',
          rows: report.bySource,
        ),
        _BreakdownTable(
          title: 'Execution origin',
          dimension: 'Origin',
          rows: report.byOrigin,
        ),
      ];
      if (constraints.maxWidth < IiOsBreakpoints.medium) {
        return Column(children: [cards.first, IiOsGap.vMd, cards.last]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cards.first),
          IiOsGap.hMd,
          Expanded(child: cards.last),
        ],
      );
    },
  );
}

class _CoverageNotice extends StatelessWidget {
  const _CoverageNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(IiOsSpacing.sm),
    decoration: BoxDecoration(
      color: IiOsColors.amberTint,
      border: Border.all(color: IiOsColors.amber),
      borderRadius: IiOsRadii.mdAll,
    ),
    child: const Row(
      children: [
        Icon(LucideIcons.triangleAlert, color: IiOsColors.amber, size: 18),
        IiOsGap.hXs,
        Expanded(
          child: Text(
            'Prompts were observed, but no high-confidence token events were captured. Token totals are incomplete, not zero.',
          ),
        ),
      ],
    ),
  );
}

class _DailyUsageCard extends StatelessWidget {
  const _DailyUsageCard({required this.days, required this.values});

  final int days;
  final List<DailyAgentUsage> values;

  @override
  Widget build(BuildContext context) {
    final visible = values.length > 14
        ? values.sublist(values.length - 14)
        : values;
    final maximum = visible.fold<int>(
      1,
      (value, day) => math.max(value, day.totals.totalTokens),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily tokens',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IiOsGap.vXxs,
            Text(
              'Most recent ${math.min(days, 14)} days with reported usage',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vMd,
            SizedBox(
              height: IiOsSpacing.xxxl * 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in visible)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${_date(day.date)} · ${_number(day.totals.totalTokens)} tokens',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: IiOsSpacing.xxs,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        day.totals.totalTokens / maximum,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: IiOsColors.green,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(
                                                IiOsRadii.sm,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IiOsGap.vXs,
                              Text(
                                '${day.date?.day ?? '\u2014'}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownTable extends StatelessWidget {
  const _BreakdownTable({
    required this.title,
    required this.dimension,
    required this.rows,
  });

  final String title;
  final String dimension;
  final List<AgentUsageBreakdown> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.only(top: IiOsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.md),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          IiOsGap.vXs,
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(dimension.toUpperCase())),
                    const DataColumn(numeric: true, label: Text('TOKENS')),
                    const DataColumn(numeric: true, label: Text('PROMPTS')),
                    const DataColumn(numeric: true, label: Text('API EQUIV.')),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          DataCell(Text(_displayName(row.name))),
                          DataCell(Text(_compact(row.totals.totalTokens))),
                          DataCell(
                            Text(
                              row.totals.prompts == 0
                                  ? '\u2014'
                                  : _number(row.totals.prompts),
                            ),
                          ),
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

String _number(int value) {
  final source = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < source.length; index++) {
    if (index > 0 && (source.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(source[index]);
  }
  return buffer.toString();
}

String _compact(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}K';
  }
  return '${(value / 1000000).toStringAsFixed(value < 10000000 ? 1 : 0)}M';
}

String _date(DateTime? value) => value == null
    ? 'Unknown date'
    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _displayName(String value) => switch (value) {
  'codex' => 'Codex',
  'claude-code' => 'Claude Code',
  'local' => 'Local',
  'cloud' => 'Cloud',
  'unknown' => 'Unknown',
  _ => value,
};
