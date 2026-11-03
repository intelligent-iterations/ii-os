@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_usage.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/navigation/app_route_state.dart';
import 'package:ii_os/repositories/fleet_repository.dart';
import 'package:ii_os/repositories/people_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/agent_permissions_screen.dart';
import 'package:ii_os/screens/agent_usage_screen.dart';
import 'package:ii_os/screens/characters_screen.dart';
import 'package:ii_os/screens/fleet_screen.dart';
import 'package:ii_os/screens/generate_screen.dart';
import 'package:ii_os/screens/github_setup_screen.dart';
import 'package:ii_os/screens/history_screen.dart';
import 'package:ii_os/screens/interactive_sessions_screen.dart';
import 'package:ii_os/screens/home_screen.dart';
import 'package:ii_os/screens/image_edit_panel.dart';
import 'package:ii_os/screens/jobs_screen.dart';
import 'package:ii_os/screens/narration_generation_screen.dart';
import 'package:ii_os/screens/organization_resources_screen.dart';
import 'package:ii_os/screens/people_screen.dart';
import 'package:ii_os/screens/playground_screen.dart';
import 'package:ii_os/screens/production_line_screen.dart';
import 'package:ii_os/screens/project_admin_page.dart';
import 'package:ii_os/screens/software_workshop_screen.dart';
import 'package:ii_os/screens/song_generation_screen.dart';
import 'package:ii_os/screens/storyboards_screen.dart';
import 'package:ii_os/screens/video_editor_screen.dart';
import 'package:ii_os/screens/video_generation_screen.dart';
import 'package:ii_os/screens/workspace_resource_selection_screen.dart';
import 'package:ii_os/state/app_controller.dart';

import 'page_golden_harness.dart';
import 'page_golden_interactive_fixture.dart';

/// One golden per routed page, at the desktop viewport.
///
/// The list mirrors `AppPage`; a page added there without a case here is a page
/// nobody is looking at. Each builder takes the seeded controller and returns
/// the screen exactly as `operator_shell.dart` constructs it, so the golden
/// shows the real page rather than a simplified stand-in.
typedef PageBuilder = Widget Function(AppController controller);

final _pages = <String, PageBuilder>{
  'home': (c) => HomeScreen(controller: c),
  'github-setup': (c) => GitHubSetupScreen(
    controller: c,
    repository: null,
    step: null,
    onRepositoryChanged: _ignoreString,
    onStepChanged: _ignoreString,
    onOpenWorkshop: _ignore,
  ),
  'project-admin': (c) => ProjectAdminPage(
    controller: c,
    tab: ProjectAdminTab.settings,
    onTabChanged: (_) {},
  ),
  'workspace-resources': (c) => WorkspaceResourceSelectionScreen(
    controller: seedResourcePageController(c),
  ),
  'organization-resources': (c) =>
      OrganizationResourcesScreen(controller: seedResourcePageController(c)),
  'tickets': (c) => SoftwareWorkshopScreen(
    controller: c,
    onSelectionChanged: (_, _, _, _) {},
    onRoomChanged: (_, _, _) {},
    onManagePermissions: _ignoreRequiredString,
    onReviewSetup: _ignore,
    onConfigureProjects: _ignore,
  ),
  'production-line': (c) => ProductionLineScreen(
    controller: c,
    lineId: '',
    onOpenGitHub: _ignoreRequiredString,
    onManagePermissions: _ignoreRequiredString,
  ),
  'agent-permissions': (c) => AgentPermissionsScreen(controller: c),
  'agent-usage': (c) => AgentUsageScreen(
    controller: c,
    days: 30,
    origin: AgentExecutionOrigin.all,
    loader: ({required workspaceId, required days, required origin}) async =>
        _agentUsageFixture,
  ),
  'infrastructure': (c) => FleetScreen(
    controller: c,
    repository: const _DisconnectedFleetRepository(),
  ),
  'playground': (c) => PlaygroundScreen(
    controller: c,
    templateRepository: const _EmptyWorkflowTemplateRepository(),
  ),
  'characters': (c) => CharactersScreen(controller: c),
  'storyboards': (c) => StoryboardsScreen(controller: c),
  'images': (c) => GenerateScreen(
    controller: c,
    templateRepository: const _EmptyWorkflowTemplateRepository(),
  ),
  'image-edit': (c) => ImageEditScreen(
    controller: c,
    templateRepository: const _EmptyWorkflowTemplateRepository(),
  ),
  'video-generation': (c) => VideoGenerationScreen(controller: c),
  'video-editor': (c) => VideoEditorScreen(controller: c),
  'songs': (c) => SongGenerationScreen(controller: c),
  'narration': (c) => NarrationGenerationScreen(controller: c),
  'history': (c) => HistoryScreen(controller: c),
  'jobs': (c) => JobsScreen(controller: c),
  'terminal-sessions': (c) => InteractiveSessionsScreen(
    controller: c,
    repository: emptyInteractiveSessionRepository,
  ),
  'people': (c) => PeopleScreen(
    controller: seedResourcePageController(c),
    repository: const _PagePeopleRepository(),
  ),
};

/// Pages that cannot be captured yet, and why.
const _uncapturablePages = <String, String>{
  // Excluded rather than captured because the page reads live runner host
  // state and has no fixture yet.
  'infrastructure': 'renders live Fleet host state with no fixture',
};

// Navigation callbacks. A golden captures one page at rest, so nothing here
// needs to route anywhere -- but the parameters are required, and passing real
// no-ops keeps the constructors identical to `operator_shell.dart`.
void _ignore() {}
void _ignoreString(String? _) {}
void _ignoreRequiredString(String _) {}

final class _DisconnectedFleetRepository implements FleetRepository {
  const _DisconnectedFleetRepository();

  @override
  Future<FleetReport?> read(String organizationId) async => null;

  @override
  Future<String> issueCredential({
    required String organizationId,
    required String label,
  }) => throw UnsupportedError('The page golden never issues credentials.');
}

final class _EmptyWorkflowTemplateRepository
    implements WorkflowTemplateRepository {
  const _EmptyWorkflowTemplateRepository();

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async => const [];
}

final class _PagePeopleRepository implements PeopleRepository {
  const _PagePeopleRepository();

  @override
  Future<OrganizationPeopleModel> loadDirectory(String organizationId) async =>
      _pagePeople;

  @override
  Future<List<WorkspaceAssignmentModel>> loadWorkspaceAccess({
    required String organizationId,
    required String uid,
  }) async => const [];

  @override
  Future<PeopleInviteResult> invite({
    required String organizationId,
    required String email,
    required String role,
    required List<String> workspaceIds,
  }) => throw UnsupportedError('The page golden never sends invitations.');

  @override
  Future<void> revokeInvitation({
    required String organizationId,
    required String invitationId,
  }) => throw UnsupportedError('The page golden never revokes invitations.');

  @override
  Future<WorkspaceAccessChangeModel> setWorkspaceAccess({
    required String organizationId,
    required String workspaceId,
    required String uid,
    required bool suspended,
  }) => throw UnsupportedError('The page golden never changes access.');

  @override
  Future<OrganizationPersonModel> updateOrganizationMember({
    required String organizationId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  }) => throw UnsupportedError('The page golden never edits people.');

  @override
  Future<WorkspaceAssignmentModel> updateWorkspaceMember({
    required String workspaceId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  }) => throw UnsupportedError('The page golden never edits permissions.');

  @override
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String uid,
  }) => throw UnsupportedError('The page golden never removes people.');

  @override
  Future<void> deleteOrganization(String organizationId) =>
      throw UnsupportedError('The page golden never deletes organizations.');
}

const _pagePeople = OrganizationPeopleModel(
  people: [
    OrganizationPersonModel(
      uid: 'owner-1',
      email: 'owner@acme.example',
      role: 'owner',
      roleLabel: 'Organization Owner',
    ),
    OrganizationPersonModel(
      uid: 'person-1',
      email: 'person@example.com',
      role: 'member',
      roleLabel: 'Organization Member',
    ),
    OrganizationPersonModel(
      uid: 'producer-1',
      email: 'producer@acme.example',
      role: 'member',
      roleLabel: 'Organization Member',
    ),
  ],
  workspaces: [
    OrganizationWorkspaceModel(
      id: 'workspace-1',
      name: 'Media operations',
      environment: 'dev',
    ),
    OrganizationWorkspaceModel(
      id: 'workspace-campaigns',
      name: 'Campaign production',
      environment: 'prod',
    ),
  ],
  invitations: [
    OrganizationInvitationModel(
      id: 'invite-1',
      email: 'new.producer@acme.example',
      role: 'member',
      roleLabel: 'Organization Member',
      workspaceIds: ['workspace-1', 'workspace-campaigns'],
      deliveryStatus: 'delivered',
      expiresAt: null,
    ),
  ],
);

final _agentUsageFixture = AgentUsageReport(
  configured: true,
  generatedAt: DateTime.utc(2026, 8, 16, 12),
  days: 30,
  origin: AgentExecutionOrigin.all,
  summary: const AgentUsageTotals(
    prompts: 184,
    sessions: 42,
    requests: 173,
    inputTokens: 2640000,
    cachedInputTokens: 1180000,
    cacheReadInputTokens: 1080000,
    cacheCreationInputTokens: 100000,
    outputTokens: 382000,
    reasoningOutputTokens: 91000,
    totalTokens: 3022000,
    costUsd: 24.68,
    actualCostUsd: 0,
  ),
  bySource: const [
    AgentUsageBreakdown(
      name: 'codex',
      totals: AgentUsageTotals(
        prompts: 139,
        sessions: 31,
        requests: 132,
        inputTokens: 2060000,
        cachedInputTokens: 980000,
        cacheReadInputTokens: 980000,
        cacheCreationInputTokens: 0,
        outputTokens: 298000,
        reasoningOutputTokens: 91000,
        totalTokens: 2358000,
        costUsd: 17.44,
      ),
    ),
    AgentUsageBreakdown(
      name: 'claude-code',
      totals: AgentUsageTotals(
        prompts: 45,
        sessions: 11,
        requests: 41,
        inputTokens: 580000,
        cachedInputTokens: 200000,
        cacheReadInputTokens: 100000,
        cacheCreationInputTokens: 100000,
        outputTokens: 84000,
        reasoningOutputTokens: 0,
        totalTokens: 664000,
        costUsd: 7.24,
      ),
    ),
  ],
  byModel: const [
    AgentUsageBreakdown(
      name: 'gpt-5.6-sol',
      totals: AgentUsageTotals(
        prompts: 0,
        sessions: 24,
        requests: 104,
        inputTokens: 1720000,
        cachedInputTokens: 870000,
        cacheReadInputTokens: 870000,
        cacheCreationInputTokens: 0,
        outputTokens: 241000,
        reasoningOutputTokens: 72000,
        totalTokens: 1961000,
        costUsd: 14.83,
      ),
    ),
    AgentUsageBreakdown(
      name: 'claude-sonnet-4-5',
      totals: AgentUsageTotals(
        prompts: 0,
        sessions: 11,
        requests: 41,
        inputTokens: 580000,
        cachedInputTokens: 200000,
        cacheReadInputTokens: 100000,
        cacheCreationInputTokens: 100000,
        outputTokens: 84000,
        reasoningOutputTokens: 0,
        totalTokens: 664000,
        costUsd: 7.24,
      ),
    ),
    AgentUsageBreakdown(
      name: 'gpt-5.6-luna',
      totals: AgentUsageTotals(
        prompts: 0,
        sessions: 7,
        requests: 28,
        inputTokens: 340000,
        cachedInputTokens: 110000,
        cacheReadInputTokens: 110000,
        cacheCreationInputTokens: 0,
        outputTokens: 57000,
        reasoningOutputTokens: 19000,
        totalTokens: 397000,
        costUsd: 2.61,
      ),
    ),
  ],
  byOrigin: const [
    AgentUsageBreakdown(
      name: 'local',
      totals: AgentUsageTotals(
        prompts: 122,
        sessions: 28,
        requests: 115,
        inputTokens: 1890000,
        cachedInputTokens: 840000,
        cacheReadInputTokens: 790000,
        cacheCreationInputTokens: 50000,
        outputTokens: 267000,
        reasoningOutputTokens: 65000,
        totalTokens: 2157000,
        costUsd: 16.97,
      ),
    ),
    AgentUsageBreakdown(
      name: 'cloud',
      totals: AgentUsageTotals(
        prompts: 62,
        sessions: 14,
        requests: 58,
        inputTokens: 750000,
        cachedInputTokens: 340000,
        cacheReadInputTokens: 290000,
        cacheCreationInputTokens: 50000,
        outputTokens: 115000,
        reasoningOutputTokens: 26000,
        totalTokens: 865000,
        costUsd: 7.71,
      ),
    ),
  ],
  allocations: const [
    AgentUsageAllocation(
      jobName: 'nightly-report',
      model: 'gpt-5.6-sol',
      billingMode: AgentBillingMode.subscriptionIncluded,
      billingProvider: 'openai',
      billingPlan: 'chatgpt-pro',
      totals: AgentUsageTotals(
        prompts: 0,
        sessions: 24,
        requests: 104,
        inputTokens: 1720000,
        cachedInputTokens: 870000,
        cacheReadInputTokens: 870000,
        cacheCreationInputTokens: 0,
        outputTokens: 241000,
        reasoningOutputTokens: 72000,
        totalTokens: 1961000,
        costUsd: 14.83,
        actualCostUsd: 0,
      ),
    ),
    AgentUsageAllocation(
      jobName: 'work-ticket',
      model: 'gpt-5.6-luna',
      billingMode: AgentBillingMode.subscriptionIncluded,
      billingProvider: 'openai',
      billingPlan: 'chatgpt-pro',
      totals: AgentUsageTotals(
        prompts: 0,
        sessions: 7,
        requests: 28,
        inputTokens: 340000,
        cachedInputTokens: 110000,
        cacheReadInputTokens: 110000,
        cacheCreationInputTokens: 0,
        outputTokens: 57000,
        reasoningOutputTokens: 19000,
        totalTokens: 397000,
        costUsd: 2.61,
        actualCostUsd: 0,
      ),
    ),
  ],
  subscriptions: const [
    AgentUsageSubscription(
      billingProvider: 'openai',
      billingPlan: 'chatgpt-pro',
      monthlyCostUsd: 200,
      totals: AgentUsageTotals(
        prompts: 139,
        sessions: 31,
        requests: 132,
        inputTokens: 2060000,
        cachedInputTokens: 980000,
        cacheReadInputTokens: 980000,
        cacheCreationInputTokens: 0,
        outputTokens: 298000,
        reasoningOutputTokens: 91000,
        totalTokens: 2358000,
        costUsd: 17.44,
        actualCostUsd: 0,
      ),
    ),
  ],
  daily: [
    for (var index = 0; index < 14; index++)
      DailyAgentUsage(
        date: DateTime.utc(2026, 8, 3 + index),
        totals: AgentUsageTotals(
          prompts: 8 + index,
          sessions: 2,
          requests: 8 + index,
          inputTokens: 90000 + index * 11000,
          cachedInputTokens: 35000 + index * 5000,
          cacheReadInputTokens: 35000 + index * 5000,
          cacheCreationInputTokens: 0,
          outputTokens: 18000 + index * 1700,
          reasoningOutputTokens: 3000 + index * 600,
          totalTokens: 108000 + index * 12700,
          costUsd: 0.85 + index * 0.12,
        ),
      ),
  ],
  coverage: const AgentUsageCoverage(
    usageEvents: 173,
    claudeOtelRequests: 41,
    claudeStatuslineSamples: 9,
    codexTokenEvents: 132,
  ),
  byMode: const [
    AgentModeUsage(
      mode: AgentRunMode.interactive,
      totals: AgentUsageTotals(
        prompts: 45,
        sessions: 11,
        requests: 41,
        inputTokens: 580000,
        cachedInputTokens: 200000,
        cacheReadInputTokens: 100000,
        cacheCreationInputTokens: 100000,
        outputTokens: 84000,
        reasoningOutputTokens: 0,
        totalTokens: 664000,
        costUsd: 7.24,
      ),
      sessions: AgentSessionStats(
        sessions: 11,
        measuredSessions: 9,
        medianSeconds: 4230,
        p90Seconds: 9120,
        longestSeconds: 11400,
        totalSeconds: 52800,
      ),
    ),
    AgentModeUsage(
      mode: AgentRunMode.automated,
      totals: AgentUsageTotals(
        prompts: 139,
        sessions: 31,
        requests: 132,
        inputTokens: 2060000,
        cachedInputTokens: 980000,
        cacheReadInputTokens: 980000,
        cacheCreationInputTokens: 0,
        outputTokens: 298000,
        reasoningOutputTokens: 91000,
        totalTokens: 2358000,
        costUsd: 17.44,
      ),
      sessions: AgentSessionStats(
        sessions: 31,
        measuredSessions: 22,
        medianSeconds: 540,
        p90Seconds: 1260,
        longestSeconds: 2100,
        totalSeconds: 19800,
      ),
    ),
  ],
  sessions: const AgentSessionStats(
    sessions: 42,
    measuredSessions: 31,
    medianSeconds: 960,
    p90Seconds: 7800,
    longestSeconds: 11400,
    totalSeconds: 72600,
  ),
  bytesProcessed: 94630,
  truncated: false,
);

/// The golden file a page is compared against.
String _goldenName(String page) {
  return page;
}

void main() {
  setUpAll(loadPageFonts);

  test('every routed page is captured or explicitly excluded', () {
    // The list above is hand-written, so this is what stops a new page from
    // being added to AppPage and silently never looked at again.
    final covered = {..._pages.keys, ..._uncapturablePages.keys};
    final missing = AppPage.values
        .map((page) => page.slug)
        .where((slug) => !covered.contains(slug))
        .toList();

    expect(missing, isEmpty, reason: 'add a golden or an explicit exclusion');
  });

  for (final entry in _pages.entries) {
    testWidgets(entry.key, (tester) async {
      final controller = pageController();
      addTearDown(controller.dispose);

      await pumpPage(tester, entry.value(controller));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/pages/${_goldenName(entry.key)}.png'),
      );
    });
  }
}
