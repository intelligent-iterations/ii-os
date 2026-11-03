/// SQL and result shaping for the workspace agent-usage report.
///
/// The report is produced by a **single** aggregated query rather than by
/// reading raw rows and summing them in Dart. Reading raw rows capped the
/// report at whatever `maxResults` happened to be and truncated silently once a
/// workspace crossed it; aggregating in BigQuery returns a bounded handful of
/// rows no matter how much usage the window holds, and scans the table once.
library;

/// Rows are written one per usage event.
///
/// Older rows fanned each event into three (`summary`, `source`, `model`)
/// carrying identical metrics, which tripled both storage and every scan. The
/// current shape is a single `event` row carrying both labels. Both shapes are
/// read here so no history is lost: selecting the summary-equivalent of each
/// counts every event exactly once.
const String agentUsageEventRowKind = 'event';
const List<String> legacyAgentUsageRowKinds = ['summary', 'source', 'model'];

/// How a run is classified when reporting interactive vs automated usage.
///
/// A Fleet job, lease, or stream id means the run was dispatched by automation,
/// as does a `cloud` execution origin. A `local` origin with no such id is
/// somebody at a keyboard. Anything else stays `unknown` rather than being
/// guessed into one of the two.
const String interactiveRunMode = 'interactive';
const String automatedRunMode = 'automated';
const String unknownRunMode = 'unknown';

/// Upper bound on returned rows. The result is one row per bucket -- totals,
/// one per source/model/origin/mode/day, plus session statistics -- so this is
/// far above any real shape and exists only so pathological label cardinality
/// cannot turn into an unbounded response.
const int agentUsageRowLimit = 1000;

// `sessions` is deliberately absent: the ingested counter only ever counted
// Codex conversation starts, while the report wants the number of distinct
// sessions actually observed. That comes from COUNT(DISTINCT
// session_fingerprint) below, so the stored column is never scanned.
const List<String> _countMetricColumns = [
  'prompts',
  'requests',
  'input_tokens',
  'cached_input_tokens',
  'cache_read_input_tokens',
  'cache_creation_input_tokens',
  'output_tokens',
  'reasoning_output_tokens',
  'total_tokens',
  'usage_events',
  'claude_otel_requests',
  'claude_statusline_samples',
  'codex_token_events',
];

const List<String> _sessionColumns = [
  'session_count',
  'measured_sessions',
  'seconds_p50',
  'seconds_p90',
  'seconds_max',
  'seconds_total',
];

String get _metricAggregates => [
  for (final column in _countMetricColumns) '    SUM($column) AS $column',
  '    SUM(COALESCE(api_equivalent_cost_usd, cost_usd)) AS cost_usd',
  '    SUM(COALESCE(api_equivalent_cost_usd, cost_usd)) AS api_equivalent_cost_usd',
  '    SUM(COALESCE(actual_cost_usd, 0)) AS actual_cost_usd',
  '    COUNTIF(actual_cost_usd IS NULL) AS actual_cost_unknown_events',
  '    COUNT(DISTINCT session_fingerprint) AS distinct_sessions',
].join(',\n');

String get _nullMetrics => [
  for (final column in _countMetricColumns)
    '    CAST(NULL AS INT64) AS $column',
  '    CAST(NULL AS NUMERIC) AS cost_usd',
  '    CAST(NULL AS NUMERIC) AS api_equivalent_cost_usd',
  '    CAST(NULL AS NUMERIC) AS actual_cost_usd',
  '    CAST(NULL AS INT64) AS actual_cost_unknown_events',
  '    CAST(NULL AS INT64) AS distinct_sessions',
].join(',\n');

String get _nullSessions => [
  for (final column in _sessionColumns) '    CAST(NULL AS INT64) AS $column',
].join(',\n');

String get _sessionAggregates => '''
    COUNT(*) AS session_count,
    COUNTIF(event_count > 1) AS measured_sessions,
    APPROX_QUANTILES(IF(event_count > 1, seconds, NULL), 100)[SAFE_OFFSET(50)] AS seconds_p50,
    APPROX_QUANTILES(IF(event_count > 1, seconds, NULL), 100)[SAFE_OFFSET(90)] AS seconds_p90,
    MAX(seconds) AS seconds_max,
    SUM(seconds) AS seconds_total''';

/// Builds the single aggregated report query for [qualifiedTable].
///
/// Named parameters: `@scope_id`, `@since_date`, `@until_date`, `@origin`.
/// `period_date` is the table's partition column and the table requires a
/// partition filter, so the date range both satisfies that requirement and
/// keeps the scan proportional to the window rather than to all history.
String agentUsageReportSql(String qualifiedTable) {
  return '''
WITH deduplicated AS (
  SELECT
    report_id,
    row_kind,
    period_date,
    period_start,
    period_end,
    execution_origin,
    agent_source,
    model,
    COALESCE(
      REGEXP_EXTRACT(fleet_job_id, r'([^:]+)\$'),
      'unknown'
    ) AS job_name,
    billing_mode,
    billing_provider,
    billing_plan,
    subscription_cost_usd_monthly,
    session_fingerprint,
    CASE
      WHEN fleet_job_id IS NOT NULL
        OR fleet_lease_id IS NOT NULL
        OR stream_id IS NOT NULL
        OR execution_origin = 'cloud' THEN '$automatedRunMode'
      WHEN execution_origin = 'local' THEN '$interactiveRunMode'
      ELSE '$unknownRunMode'
    END AS run_mode,
    ${_countMetricColumns.join(',\n    ')},
    cost_usd,
    api_equivalent_cost_usd,
    actual_cost_usd
  FROM `$qualifiedTable`
  WHERE scope_id = @scope_id
    AND period_date BETWEEN @since_date AND @until_date
    AND (@origin = 'all' OR execution_origin = @origin)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY report_id, row_kind, COALESCE(agent_source, ''), COALESCE(model, '')
    ORDER BY generated_at DESC
  ) = 1
),
scoped AS (
  SELECT *
  FROM deduplicated
  QUALIFY row_kind = '$agentUsageEventRowKind'
    OR COUNTIF(row_kind = '$agentUsageEventRowKind') OVER (
      PARTITION BY report_id
    ) = 0
),
events AS (
  SELECT * FROM scoped WHERE row_kind IN ('summary', '$agentUsageEventRowKind')
),
spans_by_mode AS (
  SELECT
    run_mode,
    session_fingerprint,
    COUNT(*) AS event_count,
    TIMESTAMP_DIFF(MAX(period_end), MIN(period_start), SECOND) AS seconds
  FROM events
  WHERE session_fingerprint IS NOT NULL
  GROUP BY run_mode, session_fingerprint
),
spans_all AS (
  SELECT
    session_fingerprint,
    COUNT(*) AS event_count,
    TIMESTAMP_DIFF(MAX(period_end), MIN(period_start), SECOND) AS seconds
  FROM events
  WHERE session_fingerprint IS NOT NULL
  GROUP BY session_fingerprint
)
SELECT 'total' AS bucket, '' AS label,
$_metricAggregates,
$_nullSessions
FROM events
UNION ALL
SELECT 'source', COALESCE(agent_source, 'unknown'),
$_metricAggregates,
$_nullSessions
FROM scoped WHERE row_kind IN ('source', '$agentUsageEventRowKind') GROUP BY 2
UNION ALL
SELECT 'model', COALESCE(model, 'unknown'),
$_metricAggregates,
$_nullSessions
FROM scoped WHERE row_kind IN ('model', '$agentUsageEventRowKind') GROUP BY 2
UNION ALL
SELECT 'origin', execution_origin,
$_metricAggregates,
$_nullSessions
FROM events GROUP BY 2
UNION ALL
SELECT 'mode', run_mode,
$_metricAggregates,
$_nullSessions
FROM events GROUP BY 2
UNION ALL
SELECT 'daily', CAST(period_date AS STRING),
$_metricAggregates,
$_nullSessions
FROM events GROUP BY 2
UNION ALL
SELECT
  'allocation',
  TO_JSON_STRING(STRUCT(
    job_name AS jobName,
    COALESCE(model, 'unknown') AS model,
    COALESCE(billing_mode, 'unknown') AS billingMode,
    COALESCE(billing_provider, 'unknown') AS billingProvider,
    COALESCE(billing_plan, 'unknown') AS billingPlan
  )),
$_metricAggregates,
$_nullSessions
FROM events
GROUP BY job_name, model, billing_mode, billing_provider, billing_plan
UNION ALL
SELECT
  'subscription',
  TO_JSON_STRING(STRUCT(
    COALESCE(billing_provider, 'unknown') AS billingProvider,
    COALESCE(billing_plan, 'unknown') AS billingPlan,
    MAX(subscription_cost_usd_monthly) AS monthlyCostUsd
  )),
$_metricAggregates,
$_nullSessions
FROM events
WHERE billing_mode = 'subscription_included'
GROUP BY billing_provider, billing_plan
UNION ALL
SELECT 'session', run_mode,
$_nullMetrics,
$_sessionAggregates
FROM spans_by_mode GROUP BY 2
UNION ALL
SELECT 'session', '',
$_nullMetrics,
$_sessionAggregates
FROM spans_all
ORDER BY bucket, label
LIMIT $agentUsageRowLimit
''';
}
