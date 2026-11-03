import 'package:ii_os_functions/src/agent_usage_event.dart';
import 'package:ii_os_functions/src/agent_usage_query.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 12);

  test('writes a safe usage event as one row carrying both labels', () {
    final event = AgentUsageEvent.parse(_event(), now: now);
    final rows = event.bigQueryRows(
      workspaceId: 'workspace-1',
      reporterId: 'key:key-1',
      receivedAt: now,
    );

    // One row per event. The old three-row fan-out repeated identical metrics
    // under summary/source/model purely so the reader could bucket without
    // SQL; the reader groups in BigQuery now, so both labels ride one row.
    expect(rows, hasLength(1));
    expect(rows.single['row_kind'], agentUsageEventRowKind);
    expect(rows.single['agent_source'], 'codex');
    expect(rows.single['model'], 'gpt-5.6-sol');
    expect(rows.single['scope_id'], 'workspace-1');
    expect(rows.single['event_id'], 'fleet-job:turn-1');
    expect(rows.single['fleet_job_id'], 'job-1');
    expect(rows.single['host_id'], 'gpu-host-1');
    expect(rows.single['billing_mode'], 'subscription_included');
    expect(rows.single['billing_provider'], 'openai');
    expect(rows.single['billing_plan'], 'chatgpt-pro');
    expect(rows.single['subscription_cost_usd_monthly'], 200);
    expect(rows.single['input_tokens'], 120);
    expect(rows.single['api_equivalent_cost_usd'], 0.0042);
    expect(rows.single['actual_cost_usd'], 0);
    expect(rows.single, isNot(contains('prompt')));
  });

  test('rejects prompt text and other unsupported event fields', () {
    final event = {..._event(), 'prompt': 'never send this'};
    expect(
      () => AgentUsageEvent.parse(event, now: now),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_agent_usage_event',
        ),
      ),
    );
  });

  test('requires a SHA-256 session fingerprint', () {
    final event = {..._event(), 'sessionFingerprint': 'session-raw-id'};
    expect(
      () => AgentUsageEvent.parse(event, now: now),
      throwsA(isA<ApiError>()),
    );
  });

  test('attributes usage to unknown when the producer cannot name a model', () {
    final event = AgentUsageEvent.parse({..._event(), 'model': null}, now: now);
    final rows = event.bigQueryRows(
      workspaceId: 'workspace-1',
      reporterId: 'member:ai-1',
      receivedAt: now,
    );

    expect(rows, hasLength(1));
    expect(rows.single['row_kind'], agentUsageEventRowKind);
    expect(rows.single['model'], 'unknown');
  });

  test('accepts the GitHub issue stream emitted by the Fleet reporter', () {
    final event = AgentUsageEvent.parse({
      ..._event(),
      'fleet': {
        'jobId': 'github:123456789:1000001:1:work-ticket',
        'leaseId': 'lease-1',
        'streamId': 'github:acme-co/example-app#999',
      },
    }, now: now);
    final rows = event.bigQueryRows(
      workspaceId: 'workspace-1',
      reporterId: 'key:key-1',
      receivedAt: now,
    );

    expect(rows.first['stream_id'], 'github:acme-co/example-app#999');
  });

  test('rejects invalid host and billing classifications', () {
    expect(
      () => AgentUsageEvent.parse({
        ..._event(),
        'hostId': 'host with spaces',
      }, now: now),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => AgentUsageEvent.parse({
        ..._event(),
        'billing': {
          'mode': 'free',
          'provider': 'openai',
          'plan': 'chatgpt-pro',
        },
      }, now: now),
      throwsA(isA<ApiError>()),
    );
  });

  test(
    'keeps legacy events backward compatible and marks actual cost unknown',
    () {
      final legacy = Map<String, Object?>.from(_event())
        ..remove('hostId')
        ..remove('billing');
      final metrics = Map<String, Object?>.from(legacy['metrics']! as Map)
        ..remove('apiEquivalentCostUsd')
        ..remove('actualCostUsd');
      legacy['metrics'] = metrics;

      final row = AgentUsageEvent.parse(legacy, now: now)
          .bigQueryRows(
            workspaceId: 'workspace-1',
            reporterId: 'key:key-1',
            receivedAt: now,
          )
          .single;

      expect(row['host_id'], isNull);
      expect(row['billing_mode'], 'unknown');
      expect(row['api_equivalent_cost_usd'], row['cost_usd']);
      expect(row['actual_cost_usd'], isNull);
    },
  );
}

Map<String, Object?> _event() => {
  'schemaVersion': agentUsageEventSchemaVersion,
  'eventId': 'fleet-job:turn-1',
  'occurredAt': '2026-08-16T11:59:00Z',
  'source': 'codex',
  'eventType': 'codex.response.completed',
  'executionOrigin': 'cloud',
  'model': 'gpt-5.6-sol',
  'hostId': 'gpu-host-1',
  'billing': {
    'mode': 'subscription_included',
    'provider': 'openai',
    'plan': 'chatgpt-pro',
    'subscriptionCostUsdMonthly': 200,
  },
  'sessionFingerprint':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'fleet': {'jobId': 'job-1', 'leaseId': 'lease-1', 'streamId': 'stream-1'},
  'metrics': {
    'prompts': 1,
    'sessions': 1,
    'requests': 1,
    'inputTokens': 120,
    'cachedInputTokens': 20,
    'cacheReadInputTokens': 20,
    'cacheCreationInputTokens': 0,
    'outputTokens': 30,
    'reasoningOutputTokens': 10,
    'totalTokens': 150,
    'costUsd': 0.0042,
    'apiEquivalentCostUsd': 0.0042,
    'actualCostUsd': 0,
    'usageEvents': 1,
    'claudeOtelRequests': 0,
    'claudeStatuslineSamples': 0,
    'codexTokenEvents': 1,
  },
};
