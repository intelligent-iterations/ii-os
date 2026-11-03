import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'agent_usage_query.dart';
import 'api_error.dart';

part 'agent_usage_billing.dart';

const agentUsageEventSchemaVersion = 'ii.agent-usage.event.v1';

final class AgentUsageEvent {
  const AgentUsageEvent({
    required this.eventId,
    required this.occurredAt,
    required this.source,
    required this.eventType,
    required this.executionOrigin,
    required this.metrics,
    this.model,
    this.hostId,
    this.billing = const AgentUsageBilling.unknown(),
    this.sessionFingerprint,
    this.fleetJobId,
    this.fleetLeaseId,
    this.streamId,
  });

  factory AgentUsageEvent.parse(Map<String, Object?> json, {DateTime? now}) {
    _expectKeys(json, const {
      'schemaVersion',
      'eventId',
      'occurredAt',
      'source',
      'eventType',
      'executionOrigin',
      'model',
      'hostId',
      'billing',
      'sessionFingerprint',
      'fleet',
      'metrics',
    });
    if (json['schemaVersion'] != agentUsageEventSchemaVersion) {
      throw const ApiError(
        400,
        'invalid_agent_usage_event_schema',
        'Agent usage event schema is not supported.',
      );
    }
    final eventId = _identifier(json['eventId'], 'eventId', 200);
    final occurredAt = DateTime.tryParse(
      '${json['occurredAt'] ?? ''}',
    )?.toUtc();
    final reference = (now ?? DateTime.now()).toUtc();
    if (occurredAt == null ||
        occurredAt.isBefore(reference.subtract(const Duration(days: 370))) ||
        occurredAt.isAfter(reference.add(const Duration(minutes: 10)))) {
      throw const ApiError(
        400,
        'invalid_agent_usage_event_time',
        'Agent usage event time is outside the accepted reporting window.',
      );
    }
    final origin = _identifier(json['executionOrigin'], 'executionOrigin', 16);
    if (!const {'local', 'cloud', 'unknown'}.contains(origin)) {
      throw const ApiError(
        400,
        'invalid_agent_usage_origin',
        'Choose local, cloud, or unknown agent usage.',
      );
    }
    final fleet = _optionalMap(json['fleet'], 'fleet');
    if (fleet != null) {
      _expectKeys(fleet, const {'jobId', 'leaseId', 'streamId'});
    }
    final billingJson = _optionalMap(json['billing'], 'billing');
    final billing = billingJson == null
        ? const AgentUsageBilling.unknown()
        : AgentUsageBilling.parse(billingJson);
    final metrics = _map(json['metrics'], 'metrics');
    _expectKeys(metrics, const {
      'prompts',
      'sessions',
      'requests',
      'inputTokens',
      'cachedInputTokens',
      'cacheReadInputTokens',
      'cacheCreationInputTokens',
      'outputTokens',
      'reasoningOutputTokens',
      'totalTokens',
      'costUsd',
      'apiEquivalentCostUsd',
      'actualCostUsd',
      'usageEvents',
      'claudeOtelRequests',
      'claudeStatuslineSamples',
      'codexTokenEvents',
    });
    return AgentUsageEvent(
      eventId: eventId,
      occurredAt: occurredAt,
      source: _identifier(json['source'], 'source', 64),
      eventType: _identifier(json['eventType'], 'eventType', 100),
      executionOrigin: origin,
      model: _optionalIdentifier(json['model'], 'model', 160),
      hostId: _optionalIdentifier(json['hostId'], 'hostId', 160),
      billing: billing,
      sessionFingerprint: _optionalFingerprint(json['sessionFingerprint']),
      fleetJobId: _optionalIdentifier(fleet?['jobId'], 'fleet.jobId', 256),
      fleetLeaseId: _optionalIdentifier(
        fleet?['leaseId'],
        'fleet.leaseId',
        128,
      ),
      streamId: _optionalIdentifier(fleet?['streamId'], 'fleet.streamId', 256),
      metrics: AgentUsageMetrics.parse(metrics),
    );
  }

  final String eventId;
  final DateTime occurredAt;
  final String source;
  final String eventType;
  final String executionOrigin;
  final String? model;
  final String? hostId;
  final AgentUsageBilling billing;
  final String? sessionFingerprint;
  final String? fleetJobId;
  final String? fleetLeaseId;
  final String? streamId;
  final AgentUsageMetrics metrics;

  List<Map<String, Object?>> bigQueryRows({
    required String workspaceId,
    required String reporterId,
    required DateTime receivedAt,
  }) {
    final reportId = sha256
        .convert(utf8.encode('$workspaceId\n$eventId'))
        .toString();
    final periodDate = _dateOnly(occurredAt);
    final common = <String, Object?>{
      'scope_id': workspaceId,
      'report_id': reportId,
      'period_date': periodDate,
      'period_start': occurredAt.toIso8601String(),
      'period_end': occurredAt.toIso8601String(),
      'execution_origin': executionOrigin,
      'prompts': metrics.prompts,
      'sessions': metrics.sessions,
      'requests': metrics.requests,
      'input_tokens': metrics.inputTokens,
      'cached_input_tokens': metrics.cachedInputTokens,
      'cache_read_input_tokens': metrics.cacheReadInputTokens,
      'cache_creation_input_tokens': metrics.cacheCreationInputTokens,
      'output_tokens': metrics.outputTokens,
      'reasoning_output_tokens': metrics.reasoningOutputTokens,
      'total_tokens': metrics.totalTokens,
      'cost_usd': metrics.costUsd,
      'api_equivalent_cost_usd': metrics.apiEquivalentCostUsd,
      'actual_cost_usd': metrics.actualCostUsd,
      'usage_events': metrics.usageEvents,
      'claude_otel_requests': metrics.claudeOtelRequests,
      'claude_statusline_samples': metrics.claudeStatuslineSamples,
      'codex_token_events': metrics.codexTokenEvents,
      'generated_at': receivedAt.toIso8601String(),
      'schema_version': agentUsageEventSchemaVersion,
      'event_id': eventId,
      'event_type': eventType,
      'session_fingerprint': sessionFingerprint,
      'fleet_job_id': fleetJobId,
      'fleet_lease_id': fleetLeaseId,
      'host_id': hostId,
      'billing_mode': billing.mode,
      'billing_provider': billing.provider,
      'billing_plan': billing.plan,
      'subscription_cost_usd_monthly': billing.subscriptionCostUsdMonthly,
      'stream_id': streamId,
      'reporter_id': reporterId,
    };
    // One row per event, carrying both labels.
    //
    // This used to fan every event into three rows -- summary, source, model --
    // holding identical metrics, so that the reader could bucket by label
    // without grouping in SQL. That tripled storage and tripled the bytes every
    // report scanned. The reader now aggregates in BigQuery and understands
    // both shapes, so the labels travel together on a single row.
    return [
      {
        ...common,
        'row_kind': agentUsageEventRowKind,
        'agent_source': source,
        'model': model ?? 'unknown',
      },
    ];
  }
}

final class AgentUsageMetrics {
  const AgentUsageMetrics({
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
    required this.apiEquivalentCostUsd,
    required this.actualCostUsd,
    required this.usageEvents,
    required this.claudeOtelRequests,
    required this.claudeStatuslineSamples,
    required this.codexTokenEvents,
  });

  factory AgentUsageMetrics.parse(Map<String, Object?> json) =>
      AgentUsageMetrics(
        prompts: _count(json['prompts'], 'prompts', 10000),
        sessions: _count(json['sessions'], 'sessions', 10000),
        requests: _count(json['requests'], 'requests', 100000),
        inputTokens: _count(json['inputTokens'], 'inputTokens', 1000000000),
        cachedInputTokens: _count(
          json['cachedInputTokens'],
          'cachedInputTokens',
          1000000000,
        ),
        cacheReadInputTokens: _count(
          json['cacheReadInputTokens'],
          'cacheReadInputTokens',
          1000000000,
        ),
        cacheCreationInputTokens: _count(
          json['cacheCreationInputTokens'],
          'cacheCreationInputTokens',
          1000000000,
        ),
        outputTokens: _count(json['outputTokens'], 'outputTokens', 1000000000),
        reasoningOutputTokens: _count(
          json['reasoningOutputTokens'],
          'reasoningOutputTokens',
          1000000000,
        ),
        totalTokens: _count(json['totalTokens'], 'totalTokens', 2000000000),
        costUsd: _money(json['costUsd']),
        apiEquivalentCostUsd: json['apiEquivalentCostUsd'] == null
            ? _money(json['costUsd'])
            : _money(json['apiEquivalentCostUsd']),
        actualCostUsd: _optionalMoney(json['actualCostUsd'], 'actualCostUsd'),
        usageEvents: _count(json['usageEvents'], 'usageEvents', 100000),
        claudeOtelRequests: _count(
          json['claudeOtelRequests'],
          'claudeOtelRequests',
          100000,
        ),
        claudeStatuslineSamples: _count(
          json['claudeStatuslineSamples'],
          'claudeStatuslineSamples',
          100000,
        ),
        codexTokenEvents: _count(
          json['codexTokenEvents'],
          'codexTokenEvents',
          100000,
        ),
      );

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
  final double? actualCostUsd;
  final int usageEvents;
  final int claudeOtelRequests;
  final int claudeStatuslineSamples;
  final int codexTokenEvents;
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw ApiError(400, 'invalid_agent_usage_event', '$field must be an object.');
}

Map<String, Object?>? _optionalMap(Object? value, String field) =>
    value == null ? null : _map(value, field);

void _expectKeys(Map<String, Object?> json, Set<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const ApiError(
      400,
      'invalid_agent_usage_event',
      'Agent usage event contains an unsupported field.',
    );
  }
}

String _identifier(Object? value, String field, int maximum) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty ||
      text.length > maximum ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]*$').hasMatch(text)) {
    throw ApiError(400, 'invalid_agent_usage_event', '$field is invalid.');
  }
  return text;
}

String? _optionalIdentifier(Object? value, String field, int maximum) {
  if (value == null) return null;
  final text = value is String ? value.trim() : '';
  if (text.isEmpty ||
      text.length > maximum ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/@+#-]*$').hasMatch(text)) {
    throw ApiError(400, 'invalid_agent_usage_event', '$field is invalid.');
  }
  return text;
}

String? _optionalFingerprint(Object? value) {
  if (value == null) return null;
  final text = value is String ? value : '';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(text)) {
    throw const ApiError(
      400,
      'invalid_agent_usage_event',
      'sessionFingerprint is invalid.',
    );
  }
  return text;
}

int _count(Object? value, String field, int maximum) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  if (number == null || number < 0 || number > maximum) {
    throw ApiError(400, 'invalid_agent_usage_event', '$field is invalid.');
  }
  return number;
}

double _money(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite || number < 0 || number > 1000000) {
    throw const ApiError(
      400,
      'invalid_agent_usage_event',
      'costUsd is invalid.',
    );
  }
  return number;
}

double? _optionalMoney(Object? value, String field) {
  if (value == null) return null;
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite || number < 0 || number > 1000000) {
    throw ApiError(400, 'invalid_agent_usage_event', '$field is invalid.');
  }
  return number;
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
