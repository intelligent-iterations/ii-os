import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/github_setup_readiness.dart';
import 'package:ii_os/screens/github_setup_screen.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  const repository = 'acme-co/example-app';

  test('GitHub setup has exactly two focused stages', () {
    final readiness = GitHubSetupReadinessModel.fromJson(
      _readinessJson(repository: repository, permissionsReady: false),
    );

    expect(readiness.stagesFor(repository).map((stage) => stage.id), [
      'repository',
      'permissions',
    ]);
    expect(readiness.stagesFor(repository).first.ready, isTrue);
    expect(readiness.stagesFor(repository).last.ready, isFalse);
    expect(readiness.readyFor(repository), isFalse);
  });

  testWidgets('permission step separates requirements from recommendation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    GitHubSetupAction? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentReadinessCard(
              readiness: GitHubSetupReadinessModel.fromJson(
                _readinessJson(repository: repository, permissionsReady: false),
              ),
              repository: repository,
              repositories: const [repository],
              step: 'permissions',
              loading: false,
              error: null,
              actionInProgress: false,
              blockedReason: (_) => null,
              onRepositoryChanged: (_) {},
              onStepChanged: (_) {},
              onAction: (action, _) => selectedAction = action,
              onOpenWorkshop: () {},
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.text('Give ii-os repository access'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Pull requests'), findsOneWidget);
    expect(
      find.text('Recommended: enable deployment verification'),
      findsOneWidget,
    );
    expect(find.textContaining('ruleset'), findsNothing);
    expect(find.textContaining('runner'), findsNothing);
    expect(find.textContaining('scheduler'), findsNothing);
    expect(find.textContaining('Codex'), findsNothing);

    await tester.ensureVisible(find.text('Open permission settings').first);
    await tester.tap(find.text('Open permission settings').first);
    expect(selectedAction, GitHubSetupAction.configureGitHubApp);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review marker task keeps its exact command on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final json = _readinessJson(repository: repository, permissionsReady: true);
    final repositoryHealth =
        (json['repositories'] as List<Object?>).single as Map<String, Object?>;
    (repositoryHealth['checks'] as List<Object?>).add(
      _check(
        'permission_bootstrap_tag',
        'action_required',
        repository,
        requiredValue: 'ii-os-agent-v4-bootstrap-abc123',
        command:
            'git tag ii-os-agent-v4-bootstrap-abc123 abc123 && git push origin ii-os-agent-v4-bootstrap-abc123',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentReadinessCard(
              readiness: GitHubSetupReadinessModel.fromJson(json),
              repository: repository,
              repositories: const [repository],
              step: 'permissions',
              loading: false,
              error: null,
              actionInProgress: false,
              blockedReason: (_) => null,
              onRepositoryChanged: (_) {},
              onStepChanged: (_) {},
              onAction: (_, _) {},
              onOpenWorkshop: () {},
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mark this commit as reviewed'), findsOneWidget);
    expect(find.textContaining('git tag ii-os-agent-v4'), findsOneWidget);
    expect(find.byTooltip('Copy the command'), findsOneWidget);
  });

  testWidgets('direct connection failure stays in step one with retry', (
    tester,
  ) async {
    GitHubSetupAction? selectedAction;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentReadinessCard(
              readiness: GitHubSetupReadinessModel.fromJson(
                _readinessJson(
                  repository: repository,
                  permissionsReady: false,
                  repositoryAccessReady: false,
                ),
              ),
              repository: repository,
              repositories: const [repository],
              step: null,
              loading: false,
              error: null,
              actionInProgress: false,
              blockedReason: (_) => null,
              onRepositoryChanged: (_) {},
              onStepChanged: (_) {},
              onAction: (action, _) => selectedAction = action,
              onOpenWorkshop: () {},
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Verify the GitHub connection'), findsOneWidget);
    await tester.tap(find.text('Check again'));
    expect(selectedAction, GitHubSetupAction.refresh);
  });

  testWidgets('verified App and permissions complete setup', (tester) async {
    var openedWorkshop = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: AgentReadinessCard(
            readiness: GitHubSetupReadinessModel.fromJson(
              _readinessJson(repository: repository, permissionsReady: true),
            ),
            repository: repository,
            repositories: const [repository],
            step: 'complete',
            loading: false,
            error: null,
            actionInProgress: false,
            blockedReason: (_) => null,
            onRepositoryChanged: (_) {},
            onStepChanged: (_) {},
            onAction: (_, _) {},
            onOpenWorkshop: () => openedWorkshop = true,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('GitHub is connected'), findsWidgets);
    await tester.tap(find.text('Open Software Workshop'));
    expect(openedWorkshop, isTrue);
  });

  testWidgets('deployment access is a visible recommendation, not a blocker', (
    tester,
  ) async {
    var openedWorkshop = false;
    GitHubSetupAction? selectedAction;
    final readiness = GitHubSetupReadinessModel.fromJson(
      _readinessJson(
        repository: repository,
        permissionsReady: true,
        deploymentPermissionReady: false,
      ),
    );

    expect(readiness.readyFor(repository), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentReadinessCard(
              readiness: readiness,
              repository: repository,
              repositories: const [repository],
              step: 'complete',
              loading: false,
              error: null,
              actionInProgress: false,
              blockedReason: (_) => null,
              onRepositoryChanged: (_) {},
              onStepChanged: (_) {},
              onAction: (action, _) => selectedAction = action,
              onOpenWorkshop: () => openedWorkshop = true,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('GitHub is connected'), findsWidgets);
    expect(
      find.text('Recommended: enable deployment verification'),
      findsOneWidget,
    );
    expect(
      find.textContaining('GitHub setup and agent work can continue'),
      findsOneWidget,
    );

    await tester.tap(find.text('Open Software Workshop'));
    expect(openedWorkshop, isTrue);
    await tester.ensureVisible(find.text('Open permission settings'));
    await tester.tap(find.text('Open permission settings'));
    expect(selectedAction, GitHubSetupAction.configureGitHubApp);
  });
}

Map<String, Object?> _readinessJson({
  required String repository,
  required bool permissionsReady,
  bool repositoryAccessReady = true,
  bool? deploymentPermissionReady,
}) {
  final healthy = repositoryAccessReady && permissionsReady;
  final deploymentReady = deploymentPermissionReady ?? permissionsReady;
  return {
    'status': healthy ? 'ready' : 'action_required',
    'checkedAt': '2026-08-16T12:00:00Z',
    'workspace': {
      'status': 'ready',
      'dispatchAllowed': true,
      'checkedAt': '2026-08-16T12:00:00Z',
      'checks': <Object?>[],
    },
    'repositories': [
      {
        'repository': repository,
        'status': healthy ? 'healthy' : 'action_required',
        'dispatchAllowed': healthy,
        'checkedAt': '2026-08-16T12:00:00Z',
        'checks': [
          _check('github_installation', 'passed', repository),
          _check('repository_selected', 'passed', repository),
          _check(
            'github_repository_access',
            repositoryAccessReady ? 'passed' : 'unable_to_verify',
            repository,
          ),
          for (final id in const [
            'github_app_actions',
            'github_app_contents',
            'github_app_deployments',
            'github_app_pull_requests',
          ])
            _check(
              id,
              id == 'github_app_deployments'
                  ? deploymentReady
                        ? 'passed'
                        : 'warning'
                  : permissionsReady
                  ? 'passed'
                  : 'action_required',
              repository,
              currentValue: id == 'github_app_deployments'
                  ? deploymentReady
                        ? 'Read-only'
                        : 'No access'
                  : permissionsReady
                  ? 'Read and write'
                  : 'No access',
              requiredValue: id == 'github_app_deployments'
                  ? 'Read-only'
                  : 'Read and write',
            ),
        ],
      },
    ],
    'checks': <Object?>[],
  };
}

Map<String, Object?> _check(
  String id,
  String status,
  String repository, {
  String currentValue = '',
  String requiredValue = '',
  String command = '',
}) => {
  'id': id,
  'label': id,
  'status': status,
  'detail': status == 'passed' ? 'Verified.' : 'Not verified.',
  'guidance': '',
  'repository': repository,
  if (currentValue.isNotEmpty) 'currentValue': currentValue,
  if (requiredValue.isNotEmpty) 'requiredValue': requiredValue,
  if (command.isNotEmpty) 'command': command,
};
