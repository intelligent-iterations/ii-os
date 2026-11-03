import 'dart:convert';

import 'agent_usage_query.dart';
import 'agent_usage_store.dart';

/// Shapes the aggregated bucket rows returned by [agentUsageReportSql] into the
/// workspace usage report.
///
/// BigQuery has already done the arithmetic; this only labels it. Every bucket
/// arrives pre-aggregated, so the report is complete regardless of how many
/// events the window holds.
Map<String, Object?> buildAgentUsageReport(
  AgentUsageQueryResult result, {
  required int days,
  required String origin,
}) {
  final bySource = <Map<String, Object?>>[];
  final byModel = <Map<String, Object?>>[];
  final byOrigin = <Map<String, Object?>>[];
  final byMode = <Map<String, Object?>>[];
  final allocations = <Map<String, Object?>>[];
  final subscriptions = <Map<String, Object?>>[];
  final daily = <Map<String, Object?>>[];
  final sessionsByMode = <Map<String, Object?>>[];
  var sessionsAll = _emptySessionStats();
  var summary = _emptyTotals();
  final coverage = <String, int>{
    'usageEvents': 0,
    'claudeOtelRequests': 0,
    'claudeStatuslineSamples': 0,
    'codexTokenEvents': 0,
  };

  for (final row in result.rows) {
    final bucket = _text(row['bucket']);
    final label = _text(row['label']);
    switch (bucket) {
      case 'total':
        summary = _totals(row);
        coverage['usageEvents'] = _integer(row['usage_events']);
        coverage['claudeOtelRequests'] = _integer(row['claude_otel_requests']);
        coverage['claudeStatuslineSamples'] = _integer(
          row['claude_statusline_samples'],
        );
        coverage['codexTokenEvents'] = _integer(row['codex_token_events']);
      case 'source':
        bySource.add({'source': _label(label), ..._totals(row)});
      case 'model':
        byModel.add({'model': _label(label), ..._totals(row)});
      case 'origin':
        byOrigin.add({'origin': _label(label), ..._totals(row)});
      case 'mode':
        byMode.add({'mode': _label(label), ..._totals(row)});
      case 'daily':
        daily.add({'date': label, ..._totals(row)});
      case 'allocation':
        allocations.add({..._jsonLabel(label), ..._totals(row)});
      case 'subscription':
        subscriptions.add({..._jsonLabel(label), ..._totals(row)});
      case 'session':
        if (label.isEmpty) {
          sessionsAll = _sessionStats(row);
        } else {
          sessionsByMode.add({'mode': label, ..._sessionStats(row)});
        }
    }
  }

  _rankByTokens(bySource);
  _rankByTokens(byModel);
  _rankByTokens(byOrigin);
  _rankByTokens(byMode);
  _rankByTokens(allocations);
  _rankByTokens(subscriptions);
  daily.sort(
    (left, right) => _text(left['date']).compareTo(_text(right['date'])),
  );
  sessionsByMode.sort(
    (left, right) => _text(left['mode']).compareTo(_text(right['mode'])),
  );

  return <String, Object?>{
    'configured': true,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'window': {'days': days, 'origin': origin},
    'summary': summary,
    'bySource': bySource,
    'byModel': byModel,
    'byOrigin': byOrigin,
    'byMode': byMode,
    'allocations': allocations,
    'subscriptions': subscriptions,
    'daily': daily,
    'sessions': {'all': sessionsAll, 'byMode': sessionsByMode},
    'coverage': coverage,
    'query': {
      'bytesProcessed': result.bytesProcessed,
      'cacheHit': result.cacheHit,
      // The row limit is far above any real bucket count; if it is ever hit the
      // report is incomplete and must say so rather than look merely small.
      'truncated': result.rows.length >= agentUsageRowLimit,
    },
  };
}

Map<String, Object?> emptyAgentUsageReport({
  required bool configured,
  required int days,
  required String origin,
}) => <String, Object?>{
  'configured': configured,
  'generatedAt': DateTime.now().toUtc().toIso8601String(),
  'window': {'days': days, 'origin': origin},
  'summary': _emptyTotals(),
  'bySource': <Object?>[],
  'byModel': <Object?>[],
  'byOrigin': <Object?>[],
  'byMode': <Object?>[],
  'allocations': <Object?>[],
  'subscriptions': <Object?>[],
  'daily': <Object?>[],
  'sessions': {'all': _emptySessionStats(), 'byMode': <Object?>[]},
  'coverage': {
    'usageEvents': 0,
    'claudeOtelRequests': 0,
    'claudeStatuslineSamples': 0,
    'codexTokenEvents': 0,
  },
  'query': {'bytesProcessed': null, 'cacheHit': null, 'truncated': false},
};

Map<String, Object?> _totals(Map<String, Object?> row) => <String, Object?>{
  'prompts': _integer(row['prompts']),
  // The observed number of distinct sessions, not the ingested counter.
  'sessions': _integer(row['distinct_sessions']),
  'requests': _integer(row['requests']),
  'inputTokens': _integer(row['input_tokens']),
  'cachedInputTokens': _integer(row['cached_input_tokens']),
  'cacheReadInputTokens': _integer(row['cache_read_input_tokens']),
  'cacheCreationInputTokens': _integer(row['cache_creation_input_tokens']),
  'outputTokens': _integer(row['output_tokens']),
  'reasoningOutputTokens': _integer(row['reasoning_output_tokens']),
  'totalTokens': _integer(row['total_tokens']),
  'costUsd': double.parse(_decimal(row['cost_usd']).toStringAsFixed(6)),
  'apiEquivalentCostUsd': double.parse(
    _decimal(row['api_equivalent_cost_usd']).toStringAsFixed(6),
  ),
  'actualCostUsd': double.parse(
    _decimal(row['actual_cost_usd']).toStringAsFixed(6),
  ),
  'actualCostUnknownEvents': _integer(row['actual_cost_unknown_events']),
};

Map<String, Object?> _emptyTotals() => <String, Object?>{
  'prompts': 0,
  'sessions': 0,
  'requests': 0,
  'inputTokens': 0,
  'cachedInputTokens': 0,
  'cacheReadInputTokens': 0,
  'cacheCreationInputTokens': 0,
  'outputTokens': 0,
  'reasoningOutputTokens': 0,
  'totalTokens': 0,
  'costUsd': 0.0,
  'apiEquivalentCostUsd': 0.0,
  'actualCostUsd': 0.0,
  'actualCostUnknownEvents': 0,
};

Map<String, Object?> _jsonLabel(String label) {
  try {
    final decoded = jsonDecode(label);
    return decoded is Map<String, Object?>
        ? decoded
        : (decoded as Map).cast<String, Object?>();
  } on Object {
    return const <String, Object?>{};
  }
}

/// Session length statistics.
///
/// A session is one reported session fingerprint, and its length is the span
/// between its first and last event in the window. A session with a single
/// event has no measurable span, so the quantiles are taken over sessions with
/// at least two events and [measuredSessions] says how many that was -- a
/// one-event session is unmeasured, not instant.
Map<String, Object?> _sessionStats(Map<String, Object?> row) =>
    <String, Object?>{
      'sessions': _integer(row['session_count']),
      'measuredSessions': _integer(row['measured_sessions']),
      'medianSeconds': _nullableInteger(row['seconds_p50']),
      'p90Seconds': _nullableInteger(row['seconds_p90']),
      'longestSeconds': _nullableInteger(row['seconds_max']),
      'totalSeconds': _integer(row['seconds_total']),
    };

Map<String, Object?> _emptySessionStats() => <String, Object?>{
  'sessions': 0,
  'measuredSessions': 0,
  'medianSeconds': null,
  'p90Seconds': null,
  'longestSeconds': null,
  'totalSeconds': 0,
};

void _rankByTokens(List<Map<String, Object?>> rows) {
  rows.sort((left, right) {
    final tokens = _integer(
      right['totalTokens'],
    ).compareTo(_integer(left['totalTokens']));
    if (tokens != 0) return tokens;
    return _text(left.values.first).compareTo(_text(right.values.first));
  });
}

String _label(String value) => value.isEmpty ? 'unknown' : value;

String _text(Object? value) => value?.toString() ?? '';

int _integer(Object? value) => int.tryParse('${value ?? ''}') ?? 0;

int? _nullableInteger(Object? value) =>
    value == null ? null : int.tryParse('$value');

double _decimal(Object? value) => double.tryParse('${value ?? ''}') ?? 0;
