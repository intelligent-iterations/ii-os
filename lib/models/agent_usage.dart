import 'models.dart';

part 'agent_usage_billing.dart';

enum AgentExecutionOrigin {
  all('all', 'All'),
  local('local', 'Local'),
  cloud('cloud', 'Cloud'),
  unknown('unknown', 'Unknown');

  const AgentExecutionOrigin(this.value, this.label);

  final String value;
  final String label;

  static AgentExecutionOrigin parse(String? value) => values.firstWhere(
    (origin) => origin.value == value,
    orElse: () => AgentExecutionOrigin.all,
  );
}

final class AgentUsageTotals {
  const AgentUsageTotals({
    required this.prompts,
    required this.sessions,
    required this.requests,
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.cacheReadInputTokens,
    required this.cacheCreationInputTokens,
    required this.outputTokens,
    required this.reasoningOutputTokens,
    required this.totalTokens,
    required this.costUsd,
    double? apiEquivalentCostUsd,
    this.actualCostUsd = 0,
    this.actualCostUnknownEvents = 0,
  }) : apiEquivalentCostUsd = apiEquivalentCostUsd ?? costUsd;

  const AgentUsageTotals.empty()
    : prompts = 0,
      sessions = 0,
      requests = 0,
      inputTokens = 0,
      cachedInputTokens = 0,
      cacheReadInputTokens = 0,
      cacheCreationInputTokens = 0,
      outputTokens = 0,
      reasoningOutputTokens = 0,
      totalTokens = 0,
      costUsd = 0,
      apiEquivalentCostUsd = 0,
      actualCostUsd = 0,
      actualCostUnknownEvents = 0;

  factory AgentUsageTotals.fromJson(JsonMap json) {
    final prompts = _integer(json['prompts']);
    final totalTokens = _integer(json['totalTokens']);
    return AgentUsageTotals(
      prompts: prompts,
      sessions: _integer(json['sessions']),
      requests: _integer(json['requests']),
      inputTokens: _integer(json['inputTokens']),
      cachedInputTokens: _integer(json['cachedInputTokens']),
      cacheReadInputTokens: _integer(json['cacheReadInputTokens']),
      cacheCreationInputTokens: _integer(json['cacheCreationInputTokens']),
      outputTokens: _integer(json['outputTokens']),
      reasoningOutputTokens: _integer(json['reasoningOutputTokens']),
      totalTokens: totalTokens,
      costUsd: _decimal(json['costUsd']),
      apiEquivalentCostUsd: _decimal(
        json['apiEquivalentCostUsd'] ?? json['costUsd'],
      ),
      actualCostUsd: _decimal(json['actualCostUsd']),
      actualCostUnknownEvents: json.containsKey('actualCostUnknownEvents')
          ? _integer(json['actualCostUnknownEvents'])
          : (prompts > 0 || totalTokens > 0 ? 1 : 0),
    );
  }

  final int prompts;
  final int sessions;
  final int requests;
  final int inputTokens;
  final int cachedInputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int outputTokens;
  final int reasoningOutputTokens;
  final int totalTokens;
  final double costUsd;
  final double apiEquivalentCostUsd;
  final double actualCostUsd;
  final int actualCostUnknownEvents;

  double get cacheRatio =>
      inputTokens == 0 ? 0 : cachedInputTokens / inputTokens;
}

final class AgentUsageBreakdown {
  const AgentUsageBreakdown({required this.name, required this.totals});

  factory AgentUsageBreakdown.fromJson(JsonMap json, String key) =>
      AgentUsageBreakdown(
        name: json[key]?.toString() ?? 'unknown',
        totals: AgentUsageTotals.fromJson(json),
      );

  final String name;
  final AgentUsageTotals totals;
}

final class DailyAgentUsage {
  const DailyAgentUsage({required this.date, required this.totals});

  factory DailyAgentUsage.fromJson(JsonMap json) => DailyAgentUsage(
    date: DateTime.tryParse(json['date']?.toString() ?? ''),
    totals: AgentUsageTotals.fromJson(json),
  );

  final DateTime? date;
  final AgentUsageTotals totals;
}

final class AgentUsageCoverage {
  const AgentUsageCoverage({
    required this.usageEvents,
    required this.claudeOtelRequests,
    required this.claudeStatuslineSamples,
    required this.codexTokenEvents,
  });

  factory AgentUsageCoverage.fromJson(JsonMap json) => AgentUsageCoverage(
    usageEvents: _integer(json['usageEvents']),
    claudeOtelRequests: _integer(json['claudeOtelRequests']),
    claudeStatuslineSamples: _integer(json['claudeStatuslineSamples']),
    codexTokenEvents: _integer(json['codexTokenEvents']),
  );

  final int usageEvents;
  final int claudeOtelRequests;
  final int claudeStatuslineSamples;
  final int codexTokenEvents;

  bool get hasTokenTelemetry => claudeOtelRequests > 0 || codexTokenEvents > 0;
}

/// Whether a run had somebody at the keyboard.
///
/// Derived from what the reporter already sends: a Fleet job, lease, or stream
/// id means automation dispatched the run, as does a cloud execution origin. A
/// local origin with no such id is interactive. Anything else stays unknown
/// rather than being guessed into one of the two.
enum AgentRunMode {
  interactive('interactive', 'Interactive'),
  automated('automated', 'Automated'),
  unknown('unknown', 'Unknown');

  const AgentRunMode(this.value, this.label);

  final String value;
  final String label;

  static AgentRunMode parse(String? value) => values.firstWhere(
    (mode) => mode.value == value,
    orElse: () => AgentRunMode.unknown,
  );
}

/// How long sessions ran.
///
/// A session is one reported session fingerprint, measured from its first
/// event to its last inside the window. A session with a single event has no
/// measurable span, so the quantiles cover [measuredSessions] only -- the rest
/// are unmeasured, not instant.
final class AgentSessionStats {
  const AgentSessionStats({
    required this.sessions,
    required this.measuredSessions,
    required this.medianSeconds,
    required this.p90Seconds,
    required this.longestSeconds,
    required this.totalSeconds,
  });

  const AgentSessionStats.empty()
    : sessions = 0,
      measuredSessions = 0,
      medianSeconds = null,
      p90Seconds = null,
      longestSeconds = null,
      totalSeconds = 0;

  factory AgentSessionStats.fromJson(JsonMap json) => AgentSessionStats(
    sessions: _integer(json['sessions']),
    measuredSessions: _integer(json['measuredSessions']),
    medianSeconds: _nullableInteger(json['medianSeconds']),
    p90Seconds: _nullableInteger(json['p90Seconds']),
    longestSeconds: _nullableInteger(json['longestSeconds']),
    totalSeconds: _integer(json['totalSeconds']),
  );

  final int sessions;
  final int measuredSessions;
  final int? medianSeconds;
  final int? p90Seconds;
  final int? longestSeconds;
  final int totalSeconds;

  bool get hasMeasuredLength => measuredSessions > 0 && medianSeconds != null;
}

final class AgentModeUsage {
  const AgentModeUsage({
    required this.mode,
    required this.totals,
    required this.sessions,
  });

  final AgentRunMode mode;
  final AgentUsageTotals totals;
  final AgentSessionStats sessions;
}

final class AgentUsageReport {
  const AgentUsageReport({
    required this.configured,
    required this.generatedAt,
    required this.days,
    required this.origin,
    required this.summary,
    required this.bySource,
    required this.byModel,
    required this.byOrigin,
    required this.daily,
    required this.coverage,
    required this.byMode,
    this.allocations = const [],
    this.subscriptions = const [],
    required this.sessions,
    required this.bytesProcessed,
    required this.truncated,
  });

  factory AgentUsageReport.fromJson(JsonMap json) {
    final window = asJsonMap(json['window']);
    return AgentUsageReport(
      configured: json['configured'] == true,
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      days: _integer(window['days']),
      origin: AgentExecutionOrigin.parse(window['origin']?.toString()),
      summary: AgentUsageTotals.fromJson(asJsonMap(json['summary'])),
      bySource: _breakdowns(json['bySource'], 'source'),
      byModel: _breakdowns(json['byModel'], 'model'),
      byOrigin: _breakdowns(json['byOrigin'], 'origin'),
      daily: _maps(json['daily']).map(DailyAgentUsage.fromJson).toList(),
      coverage: AgentUsageCoverage.fromJson(asJsonMap(json['coverage'])),
      byMode: _modes(json['byMode'], asJsonMap(json['sessions'])),
      allocations: _maps(
        json['allocations'],
      ).map(AgentUsageAllocation.fromJson).toList(),
      subscriptions: _maps(
        json['subscriptions'],
      ).map(AgentUsageSubscription.fromJson).toList(),
      sessions: AgentSessionStats.fromJson(
        asJsonMap(asJsonMap(json['sessions'])['all']),
      ),
      bytesProcessed: _nullableInteger(
        asJsonMap(json['query'])['bytesProcessed'],
      ),
      truncated: asJsonMap(json['query'])['truncated'] == true,
    );
  }

  final bool configured;
  final DateTime? generatedAt;
  final int days;
  final AgentExecutionOrigin origin;
  final AgentUsageTotals summary;
  final List<AgentUsageBreakdown> bySource;
  final List<AgentUsageBreakdown> byModel;
  final List<AgentUsageBreakdown> byOrigin;
  final List<DailyAgentUsage> daily;
  final AgentUsageCoverage coverage;
  final List<AgentModeUsage> byMode;
  final List<AgentUsageAllocation> allocations;
  final List<AgentUsageSubscription> subscriptions;
  final AgentSessionStats sessions;

  /// Bytes the report query scanned, and whether it hit its row ceiling. Both
  /// are reported so the cost and the completeness of a load can be checked
  /// rather than assumed.
  final int? bytesProcessed;
  final bool truncated;

  bool get isEmpty => summary.prompts == 0 && summary.totalTokens == 0;
}

List<AgentModeUsage> _modes(Object? value, JsonMap sessions) {
  final byMode = {
    for (final entry in _maps(sessions['byMode']))
      entry['mode']?.toString() ?? '': AgentSessionStats.fromJson(entry),
  };
  return [
    for (final entry in _maps(value))
      AgentModeUsage(
        mode: AgentRunMode.parse(entry['mode']?.toString()),
        totals: AgentUsageTotals.fromJson(entry),
        sessions:
            byMode[entry['mode']?.toString() ?? ''] ??
            const AgentSessionStats.empty(),
      ),
  ];
}

List<AgentUsageBreakdown> _breakdowns(Object? value, String key) => _maps(
  value,
).map((json) => AgentUsageBreakdown.fromJson(json, key)).toList();

List<JsonMap> _maps(Object? value) =>
    value is List<Object?> ? value.map(asJsonMap).toList() : const <JsonMap>[];

int _integer(Object? value) => switch (value) {
  final num value => value.toInt(),
  final Object value => int.tryParse(value.toString()) ?? 0,
  null => 0,
};

int? _nullableInteger(Object? value) => switch (value) {
  final num value => value.toInt(),
  final Object value => int.tryParse(value.toString()),
  null => null,
};

double _decimal(Object? value) => switch (value) {
  final num value => value.toDouble(),
  final Object value => double.tryParse(value.toString()) ?? 0,
  null => 0,
};

double? _nullableDecimal(Object? value) => switch (value) {
  final num value => value.toDouble(),
  final Object value => double.tryParse(value.toString()),
  null => null,
};
