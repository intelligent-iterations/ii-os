import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_usage.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/agent_usage_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  test('parses interactive and automated usage with session lengths', () {
    final report = AgentUsageReport.fromJson(_reportJson());

    expect(report.byMode.map((mode) => mode.mode), [
      AgentRunMode.interactive,
      AgentRunMode.automated,
    ]);
    final interactive = report.byMode.first;
    expect(interactive.totals.prompts, 9);
    expect(interactive.sessions.sessions, 3);
    expect(interactive.sessions.medianSeconds, 6762);
    expect(interactive.sessions.hasMeasuredLength, isTrue);

    // Every automated run reported one event, so no span is measurable. That
    // must read as unmeasured rather than as an instant session.
    final automated = report.byMode.last;
    expect(automated.sessions.sessions, 2);
    expect(automated.sessions.measuredSessions, 0);
    expect(automated.sessions.medianSeconds, isNull);
    expect(automated.sessions.hasMeasuredLength, isFalse);

    expect(report.sessions.sessions, 5);
    expect(report.bytesProcessed, 94630);
    expect(report.truncated, isFalse);
  });

  test('parses prompt, token, model, and execution-origin usage', () {
    final report = AgentUsageReport.fromJson(_reportJson());

    expect(report.configured, isTrue);
    expect(report.days, 30);
    expect(report.origin, AgentExecutionOrigin.all);
    expect(report.summary.prompts, 12);
    expect(report.summary.totalTokens, 123456);
    expect(report.summary.cachedInputTokens, 50000);
    expect(report.byModel.single.name, 'gpt-5.6-sol');
    expect(report.bySource.single.name, 'codex');
    expect(report.byOrigin.single.name, 'local');
    expect(report.summary.apiEquivalentCostUsd, 1.25);
    expect(report.summary.actualCostUsd, 0);
    expect(report.summary.actualCostUnknownEvents, 0);
    expect(report.allocations.single.jobName, 'work-ticket');
    expect(report.allocations.single.model, 'gpt-5.6-sol');
    expect(
      report.allocations.single.billingMode,
      AgentBillingMode.subscriptionIncluded,
    );
    expect(report.subscriptions.single.monthlyCostUsd, 200);
    expect(report.coverage.hasTokenTelemetry, isTrue);
  });

  test('does not present a legacy report as zero actual spend', () {
    final legacy = _totals(tokens: 1000, cost: 2.5)
      ..remove('apiEquivalentCostUsd')
      ..remove('actualCostUsd')
      ..remove('actualCostUnknownEvents');

    final totals = AgentUsageTotals.fromJson(legacy);

    expect(totals.apiEquivalentCostUsd, 2.5);
    expect(totals.actualCostUsd, 0);
    expect(totals.actualCostUnknownEvents, 1);
  });

  testWidgets('agent usage fits mobile and desktop viewports', (tester) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Engineering',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme-co/example-app'],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'owner-1',
          email: 'owner@example.com',
          role: 'owner',
          roleLabel: 'Owner',
          featureClaims: {},
          capabilities: {'audit.read'},
        ),
      );
    addTearDown(controller.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: AgentUsageScreen(
              controller: controller,
              days: 30,
              origin: AgentExecutionOrigin.all,
              loader:
                  ({
                    required workspaceId,
                    required days,
                    required origin,
                  }) async => AgentUsageReport.fromJson(_reportJson()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Agent usage'), findsOneWidget);
      expect(find.text('Prompts sent'), findsOneWidget);
      expect(find.text('API-equivalent cost'), findsOneWidget);
      expect(find.text('Actual variable spend'), findsOneWidget);
      expect(find.text('Jobs, models & billing'), findsOneWidget);
      expect(find.text('Agent work ticket'), findsOneWidget);
      expect(find.text('Hosts, models & billing'), findsNothing);
      expect(find.text('Monthly subscriptions'), findsOneWidget);
      expect(find.text('Spend'), findsNothing);
      expect(find.text('SPEND'), findsNothing);
      expect(find.text('123K'), findsWidgets);
      expect(find.text('gpt-5.6-sol'), findsAtLeastNWidgets(1));
      expect(find.text('Local'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

JsonMap _reportJson() => {
  'configured': true,
  'generatedAt': '2026-08-16T12:00:00Z',
  'window': {'days': 30, 'origin': 'all'},
  'summary': _totals(prompts: 12, tokens: 123456, cost: 1.25),
  'bySource': [
    {'source': 'codex', ..._totals(prompts: 12, tokens: 123456, cost: 1.25)},
  ],
  'byModel': [
    {'model': 'gpt-5.6-sol', ..._totals(tokens: 123456, cost: 1.25)},
  ],
  'byOrigin': [
    {'origin': 'local', ..._totals(prompts: 12, tokens: 123456, cost: 1.25)},
  ],
  'allocations': [
    {
      'jobName': 'work-ticket',
      'model': 'gpt-5.6-sol',
      'billingMode': 'subscription_included',
      'billingProvider': 'openai',
      'billingPlan': 'chatgpt-pro',
      ..._totals(tokens: 123456, cost: 1.25),
    },
  ],
  'subscriptions': [
    {
      'billingProvider': 'openai',
      'billingPlan': 'chatgpt-pro',
      'monthlyCostUsd': 200,
      ..._totals(tokens: 123456, cost: 1.25),
    },
  ],
  'daily': [
    {'date': '2026-08-15', ..._totals(prompts: 5, tokens: 50000, cost: 0.5)},
    {'date': '2026-08-16', ..._totals(prompts: 7, tokens: 73456, cost: 0.75)},
  ],
  'byMode': [
    {'mode': 'interactive', ..._totals(prompts: 9, tokens: 100000, cost: 1.0)},
    {'mode': 'automated', ..._totals(prompts: 3, tokens: 23456, cost: 0.25)},
  ],
  'sessions': {
    'all': _sessions(sessions: 5, measured: 3, median: 6762),
    'byMode': [
      {
        'mode': 'interactive',
        ..._sessions(sessions: 3, measured: 3, median: 6762),
      },
      {'mode': 'automated', ..._sessions(sessions: 2)},
    ],
  },
  'coverage': {
    'usageEvents': 4,
    'claudeOtelRequests': 0,
    'claudeStatuslineSamples': 0,
    'codexTokenEvents': 4,
  },
  'query': {'bytesProcessed': 94630, 'cacheHit': false, 'truncated': false},
};

JsonMap _sessions({required int sessions, int measured = 0, int? median}) => {
  'sessions': sessions,
  'measuredSessions': measured,
  'medianSeconds': median,
  'p90Seconds': median,
  'longestSeconds': median,
  'totalSeconds': median ?? 0,
};

JsonMap _totals({int prompts = 0, required int tokens, required double cost}) =>
    {
      'prompts': prompts,
      'sessions': 2,
      'requests': 4,
      'inputTokens': tokens - 1000,
      'cachedInputTokens': 50000,
      'cacheReadInputTokens': 50000,
      'cacheCreationInputTokens': 0,
      'outputTokens': 1000,
      'reasoningOutputTokens': 250,
      'totalTokens': tokens,
      'costUsd': cost,
      'apiEquivalentCostUsd': cost,
      'actualCostUsd': 0,
      'actualCostUnknownEvents': 0,
    };
