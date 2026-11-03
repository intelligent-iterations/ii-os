import 'package:ii_os_functions/src/agent_usage_query.dart';
import 'package:ii_os_functions/src/agent_usage_report.dart';
import 'package:ii_os_functions/src/agent_usage_store.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  test('shapes pre-aggregated buckets into the report', () {
    final report = buildAgentUsageReport(
      AgentUsageQueryResult(
        bytesProcessed: 94630,
        cacheHit: false,
        rows: [
          _metrics(
            bucket: 'total',
            prompts: 5,
            tokens: 180,
            cost: 0.7,
            sessions: 4,
            usageEvents: 3,
            claudeRequests: 1,
            codexTokenEvents: 2,
          ),
          _metrics(bucket: 'source', label: 'codex', tokens: 100, cost: 0.4),
          _metrics(
            bucket: 'source',
            label: 'claude-code',
            tokens: 80,
            cost: 0.3,
          ),
          _metrics(bucket: 'model', label: 'gpt-5.6-sol', tokens: 100),
          _metrics(bucket: 'model', label: 'claude-opus-5', tokens: 80),
          _metrics(bucket: 'origin', label: 'local', tokens: 80),
          _metrics(bucket: 'origin', label: 'cloud', tokens: 100),
          _metrics(bucket: 'mode', label: 'interactive', tokens: 80, cost: 0.3),
          _metrics(bucket: 'mode', label: 'automated', tokens: 100, cost: 0.4),
          _metrics(bucket: 'daily', label: '2026-08-16', tokens: 80),
          _metrics(bucket: 'daily', label: '2026-08-15', tokens: 100),
          _metrics(
            bucket: 'allocation',
            label:
                '{"jobName":"example-job","model":"gpt-5.6-sol","billingMode":"subscription_included","billingProvider":"openai","billingPlan":"chatgpt-pro"}',
            tokens: 100,
            cost: 0.4,
          ),
          _metrics(
            bucket: 'subscription',
            label:
                '{"billingProvider":"openai","billingPlan":"chatgpt-pro","monthlyCostUsd":200.0}',
            tokens: 100,
            cost: 0.4,
          ),
          _session(label: '', sessions: 4, measured: 2, p50: 900, p90: 1800),
          _session(
            label: 'interactive',
            sessions: 2,
            measured: 2,
            p50: 900,
            p90: 1800,
          ),
          _session(label: 'automated', sessions: 2),
        ],
      ),
      days: 30,
      origin: 'all',
    );

    expect(report['configured'], isTrue);
    expect(report['window'], {'days': 30, 'origin': 'all'});

    final summary = report['summary']! as Map<String, Object?>;
    expect(summary['prompts'], 5);
    expect(summary['totalTokens'], 180);
    expect(summary['costUsd'], 0.7);
    expect(summary['apiEquivalentCostUsd'], 0.7);
    expect(summary['actualCostUsd'], 0);
    expect(summary['actualCostUnknownEvents'], 0);
    // The reported session count is the number of distinct sessions observed,
    // not the ingested counter.
    expect(summary['sessions'], 4);

    // Breakdowns rank by tokens so the biggest contributor reads first.
    expect(_names(report['bySource'], 'source'), ['codex', 'claude-code']);
    expect(_names(report['byModel'], 'model'), [
      'gpt-5.6-sol',
      'claude-opus-5',
    ]);
    expect(_names(report['byOrigin'], 'origin'), ['cloud', 'local']);
    expect(_names(report['byMode'], 'mode'), ['automated', 'interactive']);
    final allocation =
        (report['allocations']! as List<Object?>).single
            as Map<String, Object?>;
    expect(allocation['jobName'], 'example-job');
    expect(allocation['model'], 'gpt-5.6-sol');
    expect(allocation['billingMode'], 'subscription_included');
    expect(allocation['apiEquivalentCostUsd'], 0.4);
    expect(allocation['actualCostUsd'], 0);
    final subscription =
        (report['subscriptions']! as List<Object?>).single
            as Map<String, Object?>;
    expect(subscription['billingPlan'], 'chatgpt-pro');
    expect(subscription['monthlyCostUsd'], 200);
    // Days read oldest first so the chart is chronological.
    expect(_names(report['daily'], 'date'), ['2026-08-15', '2026-08-16']);

    final sessions = report['sessions']! as Map<String, Object?>;
    final all = sessions['all']! as Map<String, Object?>;
    expect(all['sessions'], 4);
    expect(all['measuredSessions'], 2);
    expect(all['medianSeconds'], 900);
    expect(all['p90Seconds'], 1800);

    final automated = (sessions['byMode']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((entry) => entry['mode'] == 'automated');
    // Every automated run reported a single event, so no span is measurable --
    // that is unmeasured, not instant, and must not read as zero.
    expect(automated['sessions'], 2);
    expect(automated['measuredSessions'], 0);
    expect(automated['medianSeconds'], isNull);

    final coverage = report['coverage']! as Map<String, Object?>;
    expect(coverage['usageEvents'], 3);
    expect(coverage['claudeOtelRequests'], 1);
    expect(coverage['codexTokenEvents'], 2);

    final query = report['query']! as Map<String, Object?>;
    expect(query['bytesProcessed'], 94630);
    expect(query['cacheHit'], isFalse);
    expect(query['truncated'], isFalse);
  });

  test('flags a report that hit the row limit instead of looking small', () {
    final report = buildAgentUsageReport(
      AgentUsageQueryResult(
        rows: [
          for (var index = 0; index < agentUsageRowLimit; index++)
            _metrics(bucket: 'model', label: 'model-$index', tokens: 1),
        ],
      ),
      days: 7,
      origin: 'all',
    );

    expect((report['query']! as Map<String, Object?>)['truncated'], isTrue);
  });

  test('unconfigured storage reports an honest empty state', () async {
    final report = await AgentUsageStore(
      projectId: '',
      datasetId: '',
      tableId: '',
    ).read(workspaceId: 'workspace-1', days: 7, origin: 'local');

    expect(report['configured'], isFalse);
    expect((report['summary']! as Map)['totalTokens'], 0);
    expect((report['sessions']! as Map)['byMode'], isEmpty);
  });

  test('rejects unbounded windows and origins before querying', () async {
    final store = AgentUsageStore(
      projectId: 'project',
      datasetId: 'dataset',
      tableId: 'table',
      query: ({required workspaceId, required days, required origin}) async =>
          throw StateError('query must not run'),
    );

    await expectLater(
      store.read(workspaceId: 'workspace-1', days: 365, origin: 'all'),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_agent_usage_window',
        ),
      ),
    );
    await expectLater(
      store.read(workspaceId: 'workspace-1', days: 30, origin: 'desktop'),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_agent_usage_origin',
        ),
      ),
    );
  });

  test('ingests a bounded event batch as one row per event', () async {
    List<Map<String, Object?>>? inserted;
    final now = DateTime.utc(2026, 8, 16, 12);
    final store = AgentUsageStore(
      projectId: 'project',
      datasetId: 'dataset',
      tableId: 'table',
      clock: () => now,
      insert: (rows) async => inserted = rows,
    );

    final result = await store.ingest(
      workspaceId: 'workspace-1',
      reporterId: 'member:user-1',
      events: [_usageEvent()],
    );

    expect(result['accepted'], 1);
    expect(result['rows'], 1);
    expect(inserted, hasLength(1));
    expect(inserted!.single['reporter_id'], 'member:user-1');
    expect(inserted!.single['row_kind'], agentUsageEventRowKind);
    // Both labels travel on the same row now; the reader groups in SQL.
    expect(inserted!.single['agent_source'], 'codex');
    expect(inserted!.single['model'], 'gpt-5.6-sol');
  });

  group('report SQL', () {
    final sql = agentUsageReportSql('project.dataset.table');

    test('always filters the partition column and bounds the window', () {
      // The table requires a partition filter; without both bounds the scan is
      // no longer proportional to the requested window.
      expect(sql, contains('period_date BETWEEN @since_date AND @until_date'));
      expect(sql, contains('scope_id = @scope_id'));
      expect(sql, contains('LIMIT $agentUsageRowLimit'));
    });

    test('reads the legacy three-row shape as well as the current one', () {
      // Legacy events were fanned into summary/source/model rows. Counting the
      // summary-equivalent of each shape keeps every historical event once.
      expect(
        sql,
        contains("row_kind IN ('summary', '$agentUsageEventRowKind')"),
      );
      expect(
        sql,
        contains("row_kind IN ('source', '$agentUsageEventRowKind')"),
      );
      expect(sql, contains("row_kind IN ('model', '$agentUsageEventRowKind')"));
    });

    test('classifies fleet-dispatched and cloud runs as automated', () {
      expect(sql, contains('fleet_job_id IS NOT NULL'));
      expect(sql, contains('fleet_lease_id IS NOT NULL'));
      expect(sql, contains('stream_id IS NOT NULL'));
      expect(sql, contains("THEN '$automatedRunMode'"));
      expect(sql, contains("THEN '$interactiveRunMode'"));
    });

    test('reports Fleet job, billing basis, and both cost meanings', () {
      expect(sql, contains('REGEXP_EXTRACT(fleet_job_id'));
      expect(sql, contains('AS jobName'));
      expect(sql, contains('billing_mode'));
      expect(sql, contains('billing_provider'));
      expect(sql, contains('billing_plan'));
      expect(sql, contains('api_equivalent_cost_usd'));
      expect(sql, contains('actual_cost_usd'));
      expect(sql, contains("'allocation'"));
      expect(sql, contains("'subscription'"));
      expect(sql, contains('MAX(subscription_cost_usd_monthly)'));
      expect(sql, contains('COUNTIF(actual_cost_usd IS NULL)'));
    });

    test('prefers a current event row over its legacy three-row copy', () {
      expect(sql, contains("COUNTIF(row_kind = '$agentUsageEventRowKind')"));
      expect(sql, contains('PARTITION BY report_id'));
    });

    test('never scans the stored session counter', () {
      // Session counts come from distinct fingerprints; the ingested `sessions`
      // column only ever counted Codex conversation starts and reading it would
      // be bytes billed for nothing.
      expect(sql, isNot(contains('SUM(sessions)')));
      expect(sql, contains('COUNT(DISTINCT session_fingerprint)'));
    });
  });
}

List<String> _names(Object? value, String key) => (value! as List<Object?>)
    .cast<Map<String, Object?>>()
    .map((entry) => entry[key]! as String)
    .toList();

Map<String, Object?> _usageEvent() => {
  'schemaVersion': 'ii.agent-usage.event.v1',
  'eventId': 'event-1',
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
  },
  'metrics': {
    'prompts': 1,
    'sessions': 1,
    'requests': 1,
    'inputTokens': 10,
    'cachedInputTokens': 0,
    'cacheReadInputTokens': 0,
    'cacheCreationInputTokens': 0,
    'outputTokens': 5,
    'reasoningOutputTokens': 1,
    'totalTokens': 15,
    'costUsd': 0,
    'apiEquivalentCostUsd': 0,
    'actualCostUsd': 0,
    'usageEvents': 1,
    'claudeOtelRequests': 0,
    'claudeStatuslineSamples': 0,
    'codexTokenEvents': 1,
  },
};

/// BigQuery returns every numeric cell as a string, so the fixtures do too.
Map<String, Object?> _metrics({
  required String bucket,
  String label = '',
  int prompts = 0,
  int tokens = 0,
  double cost = 0,
  double actualCost = 0,
  int sessions = 0,
  int usageEvents = 0,
  int claudeRequests = 0,
  int codexTokenEvents = 0,
}) => {
  'bucket': bucket,
  'label': label,
  'prompts': '$prompts',
  'requests': '1',
  'input_tokens': '${tokens - 10}',
  'cached_input_tokens': '20',
  'cache_read_input_tokens': '20',
  'cache_creation_input_tokens': '0',
  'output_tokens': '10',
  'reasoning_output_tokens': '2',
  'total_tokens': '$tokens',
  'cost_usd': '$cost',
  'api_equivalent_cost_usd': '$cost',
  'actual_cost_usd': '$actualCost',
  'actual_cost_unknown_events': '0',
  'usage_events': '$usageEvents',
  'claude_otel_requests': '$claudeRequests',
  'claude_statusline_samples': '0',
  'codex_token_events': '$codexTokenEvents',
  'distinct_sessions': '$sessions',
  'session_count': null,
  'measured_sessions': null,
  'seconds_p50': null,
  'seconds_p90': null,
  'seconds_max': null,
  'seconds_total': null,
};

Map<String, Object?> _session({
  required String label,
  int sessions = 0,
  int measured = 0,
  int? p50,
  int? p90,
}) => {
  'bucket': 'session',
  'label': label,
  'prompts': null,
  'requests': null,
  'input_tokens': null,
  'cached_input_tokens': null,
  'cache_read_input_tokens': null,
  'cache_creation_input_tokens': null,
  'output_tokens': null,
  'reasoning_output_tokens': null,
  'total_tokens': null,
  'cost_usd': null,
  'api_equivalent_cost_usd': null,
  'actual_cost_usd': null,
  'actual_cost_unknown_events': null,
  'usage_events': null,
  'claude_otel_requests': null,
  'claude_statusline_samples': null,
  'codex_token_events': null,
  'distinct_sessions': null,
  'session_count': '$sessions',
  'measured_sessions': '$measured',
  'seconds_p50': p50 == null ? null : '$p50',
  'seconds_p90': p90 == null ? null : '$p90',
  'seconds_max': p90 == null ? '0' : '$p90',
  'seconds_total': '0',
};
