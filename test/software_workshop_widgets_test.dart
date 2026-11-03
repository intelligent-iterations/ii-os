import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_permission.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/workshop_ticket.dart';
import 'package:ii_os/models/workshop_pull_request.dart';
import 'package:ii_os/models/workshop_room.dart';
import 'package:ii_os/models/workshop_ticket_draft.dart';
import 'package:ii_os/screens/software_workshop_rooms.dart';
import 'package:ii_os/screens/software_workshop_ticket_widgets.dart';
import 'package:ii_os/screens/ticket_dialog.dart';
import 'package:ii_os/screens/workshop_ticket_review_dialog.dart';
import 'package:ii_os/screens/workshop_room_dialog.dart';
import 'package:ii_os/screens/workshop_ticket_delete_dialog.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  test('pull request model binds QA readiness to the merge deployment', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    final pull = WorkshopPullRequestModel.fromJson({
      'repository': 'acme/example',
      'number': 42,
      'title': 'Ship the reviewed change',
      'url': 'https://github.com/acme/example/pull/42',
      'state': 'closed',
      'merged': true,
      'mergeCommitSha': mergeSha,
      'qaDeployment': {
        'environment': 'dev',
        'sha': mergeSha,
        'state': 'success',
        'succeeded': true,
        'environmentUrl': 'https://dev.example.com',
        'logUrl': 'https://github.com/acme/example/actions/runs/99',
      },
    });

    expect(pull.readyForQa, isTrue);
    expect(pull.qaDeploymentLabel, 'Dev deployment succeeded');
    expect(pull.qaDeploymentEnvironmentUrl, 'https://dev.example.com');
  });

  test('pull request model accepts a later deployment covering the merge', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    const deployedSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final pull = WorkshopPullRequestModel.fromJson({
      'repository': 'acme/example',
      'number': 42,
      'title': 'Ship the reviewed change',
      'url': 'https://github.com/acme/example/pull/42',
      'state': 'closed',
      'merged': true,
      'mergeCommitSha': mergeSha,
      'qaDeployment': {
        'environment': 'dev',
        'sha': deployedSha,
        'coversSha': mergeSha,
        'coverage': 'ancestor',
        'state': 'success',
        'succeeded': true,
      },
    });

    expect(pull.qaDeploymentSha, deployedSha);
    expect(pull.qaDeploymentCoversSha, mergeSha);
    expect(pull.readyForQa, isTrue);
  });

  testWidgets('pending ticket and detail fit mobile and desktop', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1280, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _harness(
          SingleChildScrollView(
            child: Column(
              children: [
                WorkshopTicketListCard(
                  ticket: _ticket(),
                  selected: true,
                  onSelected: () {},
                ),
                WorkshopTicketDetail(
                  ticket: _ticket(),
                  readiness: _readiness(ready: true),
                  profile: _profile(),
                  statusOptions: const [
                    {'id': 'todo', 'name': 'Todo'},
                    {'id': 'in-progress', 'name': 'In Progress'},
                  ],
                  canWrite: true,
                  busy: false,
                  onEdit: () {},
                  onDelete: () {},
                  onReview: () {},
                  onPause: () {},
                  onStatusChanged: (_) {},
                  onOpenGitHub: () {},
                  onManagePermissions: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Next: deploy'), findsOneWidget);
      expect(find.text('From idea to verified fix'), findsNothing);
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('Delete ticket'), findsOneWidget);
      expect(find.text('Installed · Repository maintainer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('deploying ticket immediately shows queue progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(),
            readiness: _readiness(ready: true),
            profile: _profile(),
            statusOptions: const [],
            canWrite: true,
            busy: true,
            deploying: true,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (_) {},
            onOpenGitHub: () {},
            onManagePermissions: () {},
          ),
        ),
      ),
    );

    expect(find.text('Sending to the runner queue'), findsOneWidget);
    expect(
      find.textContaining('creating the exact workflow run'),
      findsOneWidget,
    );
    expect(find.text('Queueing\u2026'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Deploy'), findsNothing);
  });

  testWidgets('ticket creation makes repository and Project ownership clear', (
    tester,
  ) async {
    TicketEditData? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<TicketEditData>(
                context: context,
                builder: (context) => TicketDialog(
                  heading: 'Create workshop ticket',
                  repository: 'acme-co/example-app',
                  projectId: 'project-7',
                  projects: const [
                    ProjectConnection(
                      id: 'project-7',
                      number: 7,
                      owner: 'acme-co',
                      title: 'Example tasks',
                    ),
                  ],
                  permissionProfiles: [_profile()],
                ),
              );
            },
            child: const Text('Open creator'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open creator'));
    await tester.pumpAndSettle();
    expect(find.text('acme-co/example-app'), findsOneWidget);
    expect(find.text('Workshop Project'), findsOneWidget);
    expect(find.text('Additional context (optional)'), findsNothing);
    expect(
      find.textContaining('not deployed when it is created'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'What needs to change?'),
      'Make ticket handoff obvious',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Definition of Done'),
      'The workshop displays every handoff stage.',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How will we verify it?'),
      'Run widget tests and complete dev QA.',
    );
    final create = find.widgetWithText(FilledButton, 'Create workshop ticket');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.projectId, 'project-7');
    expect(result!.state, 'open');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticket title label remains inside the dialog scroll viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<TicketEditData>(
              context: context,
              builder: (context) => TicketDialog(
                heading: 'Create workshop ticket',
                repository: 'acme-co/example-app',
                projects: const [_project],
                permissionProfiles: [_profile()],
              ),
            ),
            child: const Text('Open creator'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open creator'));
    await tester.pumpAndSettle();
    final titleField = find.widgetWithText(
      TextFormField,
      'What needs to change?',
    );
    await tester.tap(titleField);
    await tester.pumpAndSettle();

    final viewport = find.ancestor(
      of: titleField,
      matching: find.byType(SingleChildScrollView),
    );
    final label = find.text('What needs to change?');
    expect(
      tester.getTopLeft(label).dy,
      greaterThan(tester.getTopLeft(viewport).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorded pull request can be opened or approved and merged', (
    tester,
  ) async {
    var opened = false;
    var refreshed = false;
    var merged = false;
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(
              status: 'Ready for QA',
              finalPullRequestUrl:
                  'https://github.com/acme-co/example-app/pull/104',
            ),
            readiness: _readiness(ready: true),
            profile: _profile(),
            statusOptions: const [
              {'id': 'done', 'name': 'Done'},
              {'id': 'failed', 'name': 'QA failed'},
            ],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (_) {},
            onOpenGitHub: () {},
            onManagePermissions: () {},
            pullRequest: _pullRequest,
            canMergePullRequest: true,
            onOpenPullRequest: () => opened = true,
            onRefreshPullRequest: () => refreshed = true,
            onApproveAndMerge: () => merged = true,
          ),
        ),
      ),
    );

    expect(find.text('Open in GitHub'), findsOneWidget);
    expect(find.text('Refresh PR'), findsOneWidget);
    expect(find.text('Approve & merge'), findsOneWidget);
    await tester.tap(find.text('Open in GitHub'));
    await tester.tap(find.text('Refresh PR'));
    await tester.tap(find.text('Approve & merge'));
    expect(opened, isTrue);
    expect(refreshed, isTrue);
    expect(merged, isTrue);
  });

  testWidgets('a conflicted agent pull request offers an agent recovery pass', (
    tester,
  ) async {
    var requested = false;
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(
              status: 'Needs Human Input',
              finalPullRequestUrl: _conflictedPullRequest.url,
            ),
            readiness: _readiness(ready: true),
            profile: _profile(),
            statusOptions: const [],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (_) {},
            onOpenGitHub: () {},
            onManagePermissions: () {},
            pullRequest: _conflictedPullRequest,
            canMergePullRequest: true,
            onResolvePullRequestConflicts: () => requested = true,
          ),
        ),
      ),
    );

    expect(find.text('Resolve conflicts with agent'), findsOneWidget);
    await tester.tap(find.text('Resolve conflicts with agent'));
    expect(requested, isTrue);
  });

  testWidgets('workflow status is action-driven instead of freely selectable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        WorkshopTicketDetail(
          ticket: _ticket(status: 'Ready for QA'),
          readiness: _readiness(ready: true),
          profile: _profile(),
          statusOptions: const [
            {'id': 'todo', 'name': 'Todo'},
            {'id': 'progress', 'name': 'In Progress'},
            {'id': 'done', 'name': 'Done'},
            {'id': 'failed', 'name': 'QA failed'},
          ],
          canWrite: true,
          busy: false,
          onEdit: () {},
          onDelete: () {},
          onReview: () {},
          onPause: () {},
          onStatusChanged: (_) {},
          onOpenGitHub: () {},
          onManagePermissions: () {},
        ),
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('QA failed'), findsOneWidget);
    expect(find.text('QA passed · mark done'), findsOneWidget);
    expect(find.text('In Progress'), findsNothing);
  });

  testWidgets('a merged pull request waits for a successful deployment', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(
              status: 'Todo',
              agentRunStatus: 'worker_finalized',
              agentFinalStatus: 'needs_human_input',
              resultMatchesCurrentTicket: true,
              finalPullRequestUrl:
                  'https://github.com/acme-co/example-app/pull/103',
            ),
            readiness: _readiness(ready: true),
            profile: _profile(),
            statusOptions: const [
              {'id': 'qa', 'name': 'Ready for QA'},
            ],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (_) {},
            onOpenGitHub: () {},
            onManagePermissions: () {},
            pullRequest: _mergedPullRequest,
            canMergePullRequest: true,
          ),
        ),
      ),
    );

    expect(find.text('Ready for QA'), findsNothing);
    expect(find.text('Dev deployment in progress'), findsWidgets);
    expect(find.text('Answer & deploy'), findsNothing);
  });

  testWidgets('a deployed pull request exposes the QA handoff', (tester) async {
    String? selectedStatus;
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(
              status: 'Todo',
              agentRunStatus: 'worker_finalized',
              agentFinalStatus: 'needs_human_input',
              resultMatchesCurrentTicket: true,
              finalPullRequestUrl:
                  'https://github.com/acme-co/example-app/pull/103',
            ),
            readiness: _readiness(ready: true),
            profile: _profile(),
            statusOptions: const [
              {'id': 'qa', 'name': 'Ready for QA'},
            ],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (value) => selectedStatus = value,
            onOpenGitHub: () {},
            onManagePermissions: () {},
            pullRequest: _deployedPullRequest,
            canMergePullRequest: true,
          ),
        ),
      ),
    );

    expect(find.text('Ready for QA'), findsOneWidget);
    expect(find.text('Answer & deploy'), findsNothing);
    await tester.ensureVisible(find.text('Ready for QA'));
    await tester.tap(find.text('Ready for QA'));
    expect(selectedStatus, 'qa');
  });

  testWidgets('a finalized In Progress ticket can reach the QA handoff', (
    tester,
  ) async {
    String? selectedStatus;
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(
              status: 'In Progress',
              agentRunStatus: 'worker_finalized',
              agentFinalStatus: 'needs_human_input',
              resultMatchesCurrentTicket: true,
              finalPullRequestUrl:
                  'https://github.com/acme-co/example-app/pull/103',
            ),
            readiness: _readiness(ready: false),
            profile: _profile(),
            statusOptions: const [
              {'id': 'qa', 'name': 'Ready for QA'},
            ],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (value) => selectedStatus = value,
            onOpenGitHub: () {},
            onManagePermissions: () {},
            pullRequest: _deployedPullRequest,
            canMergePullRequest: true,
          ),
        ),
      ),
    );

    expect(find.text('Ready for QA'), findsOneWidget);
    await tester.ensureVisible(find.text('Ready for QA'));
    await tester.tap(find.text('Ready for QA'));
    expect(selectedStatus, 'qa');
  });

  testWidgets('healing draft is reviewable before ticket creation', (
    tester,
  ) async {
    TicketEditData? result;
    const draft = WorkshopTicketDraft(
      workspaceId: 'workspace-1',
      roomId: 'main',
      repository: 'acme-co/example-app',
      projectId: 'project-7',
      title: 'Restore mixed-media export',
      definitionOfDone: 'Mixed timelines export a playable video.',
      howToTest: 'Mix video, image, audio, and caption; export and probe it.',
      context: 'Observed error: browser renderer stopped.',
      permissionProfile: 'repository-maintainer',
      permissionRef: 'dev',
    );
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<TicketEditData>(
                context: context,
                builder: (context) => TicketDialog(
                  heading: 'Create healing ticket',
                  repository: draft.repository,
                  draft: draft,
                  projects: const [
                    ProjectConnection(
                      id: 'project-7',
                      number: 7,
                      owner: 'acme-co',
                      title: 'Example tasks',
                    ),
                  ],
                  permissionProfiles: [_profile()],
                ),
              );
            },
            child: const Text('Open healing draft'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open healing draft'));
    await tester.pumpAndSettle();
    expect(find.text('Restore mixed-media export'), findsOneWidget);
    expect(find.textContaining('Mixed timelines export'), findsOneWidget);
    expect(find.textContaining('browser renderer stopped'), findsOneWidget);

    final create = find.widgetWithText(FilledButton, 'Create workshop ticket');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(result?.projectId, 'project-7');
    expect(result?.title, 'Restore mixed-media export');
    expect(result?.permissionProfile, 'repository-maintainer');
  });

  testWidgets('ticket engine selector distinguishes local Qwen from Codex', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<TicketEditData>(
              context: context,
              builder: (context) => TicketDialog(
                heading: 'Create ticket',
                repository: 'acme/mobile',
                projects: const [_project],
                permissionProfiles: [_profile(), _qwenProfile()],
              ),
            ),
            child: const Text('Open ticket'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open ticket'));
    await tester.pumpAndSettle();
    expect(find.text('Agent engine and permissions'), findsOneWidget);
    final selectedEngine = find.text('Repository maintainer · Codex').last;
    await tester.ensureVisible(selectedEngine);
    await tester.tap(selectedEngine);
    await tester.pumpAndSettle();
    expect(find.text('Repository maintainer · Codex'), findsWidgets);
    expect(find.text('Repository maintainer · Qwen3.8 local'), findsOneWidget);
  });

  testWidgets('deployment review can select Qwen before deployment', (
    tester,
  ) async {
    WorkshopTicketReviewResult? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<WorkshopTicketReviewResult>(
                context: context,
                builder: (context) => WorkshopTicketReviewDialog(
                  ticket: _ticket(),
                  readiness: _readiness(ready: true),
                  profile: _profile(),
                  permissionProfiles: [_profile(), _qwenProfile()],
                ),
              );
            },
            child: const Text('Review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Model for this pass'), findsOneWidget);
    await tester.tap(find.text('Repository maintainer · Codex').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repository maintainer · Qwen3.8 local').last);
    await tester.pumpAndSettle();

    expect(find.text('Save model and recheck'), findsOneWidget);
    expect(find.text('Deploy'), findsNothing);
    await tester.tap(find.text('Save model and recheck'));
    await tester.pumpAndSettle();

    expect(result?.permissionProfile, 'qwen38-repository-maintainer');
    expect(result?.deploy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'human response is required before a questioned ticket is approved again',
    (tester) async {
      WorkshopTicketReviewResult? result;
      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<WorkshopTicketReviewResult>(
                  context: context,
                  builder: (context) => WorkshopTicketReviewDialog(
                    ticket: _ticket(
                      status: 'Todo',
                      agentRunStatus: 'worker_finalized',
                      agentFinalStatus: 'needs_human_input',
                      resultMatchesCurrentTicket: true,
                    ),
                    readiness: _readiness(ready: true),
                    profile: _profile(),
                    permissionProfiles: [_profile()],
                  ),
                );
              },
              child: const Text('Review'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Answer and deploy next pass'));
      await tester.pump();
      expect(
        find.text('Add an answer before deploying another pass.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField),
        'Use the existing API contract.',
      );
      await tester.tap(find.text('Answer and deploy next pass'));
      await tester.pumpAndSettle();

      expect(result?.response, 'Use the existing API contract.');
      expect(result?.deploy, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ready for QA supersedes an older agent question', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final ticket = _ticket(
      status: 'Ready for QA',
      statusOptionId: 'qa',
      agentRunStatus: 'worker_finalized',
      agentFinalStatus: 'needs_human_input',
    );
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: Column(
            children: [
              WorkshopTicketListCard(
                ticket: ticket,
                selected: true,
                onSelected: () {},
              ),
              WorkshopTicketDetail(
                ticket: ticket,
                readiness: _readiness(ready: false),
                profile: _profile(),
                statusOptions: const [
                  {'id': 'qa', 'name': 'Ready for QA'},
                  {'id': 'done', 'name': 'Done'},
                  {'id': 'failed', 'name': 'QA failed'},
                ],
                canWrite: true,
                busy: false,
                onEdit: () {},
                onDelete: () {},
                onReview: () {},
                onPause: () {},
                onStatusChanged: (_) {},
                onOpenGitHub: () {},
                onManagePermissions: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Next: verify the fix'), findsOneWidget);
    expect(find.text('Ready for your QA'), findsOneWidget);
    expect(find.textContaining('Choose QA passed'), findsOneWidget);
    expect(find.text('Agent requests human input'), findsNothing);
    expect(find.text('Answer & approve'), findsNothing);
    expect(find.textContaining('readiness checks passed'), findsNothing);
    expect(find.bySemanticsLabel('Delete ticket'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Remove this ticket from the Workshop'),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(
        'acme-co/example-app ticket 42. '
        'Make agent ticket handoff obvious. Status: Ready for QA. '
        'Next: Verify the fix.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('done ticket shows a terminal summary without queue messaging', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final ticket = _ticket(
      status: 'Done',
      statusOptionId: 'done',
      agentRunStatus: 'worker_finalized',
      agentFinalStatus: 'needs_human_input',
    );
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: Column(
            children: [
              WorkshopTicketListCard(
                ticket: ticket,
                selected: true,
                onSelected: () {},
              ),
              WorkshopTicketDetail(
                ticket: ticket,
                readiness: _readiness(ready: false),
                profile: _profile(),
                statusOptions: const [
                  {'id': 'done', 'name': 'Done'},
                  {'id': 'failed', 'name': 'QA failed'},
                ],
                canWrite: true,
                busy: false,
                onEdit: () {},
                onDelete: () {},
                onReview: () {},
                onPause: () {},
                onStatusChanged: (_) {},
                onOpenGitHub: () {},
                onManagePermissions: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('No action needed'), findsOneWidget);
    expect(find.text('Work complete'), findsOneWidget);
    expect(find.textContaining('No further Workshop action'), findsOneWidget);
    expect(find.textContaining('readiness checks passed'), findsNothing);
    expect(
      find.text(
        'Finish the current workflow step before deploying another pass.',
      ),
      findsNothing,
    );
    expect(find.text('Next action unavailable'), findsNothing);
    expect(find.text('QA failed'), findsNothing);
    expect(find.text('QA passed · mark done'), findsNothing);
    expect(
      find.bySemanticsLabel(
        'acme-co/example-app ticket 42. '
        'Make agent ticket handoff obvious. Status: Done. '
        'Next: No action needed.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry failure is explicit and offers a reviewed retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket(
              status: 'In Progress',
              agentRunStatus: 'retry_failed',
              agentRunDetail: 'The worker image is mutable.',
            ),
            readiness: _readiness(ready: true),
            profile: _profile(),
            statusOptions: const [],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReview: () {},
            onPause: () {},
            onStatusChanged: (_) {},
            onOpenGitHub: () {},
            onManagePermissions: () {},
          ),
        ),
      ),
    );

    expect(find.text('Retry failed'), findsWidgets);
    expect(find.text('The worker image is mutable.'), findsOneWidget);
    expect(find.text('Review & retry'), findsOneWidget);
    expect(find.text('Agent working'), findsNothing);
  });

  testWidgets(
    'reconciled failure can be reviewed despite stale In Progress status',
    (tester) async {
      var reviewed = false;
      await tester.pumpWidget(
        _harness(
          SingleChildScrollView(
            child: WorkshopTicketDetail(
              ticket: _ticket(
                status: 'In Progress',
                agentRunStatus: 'approval_required',
              ),
              readiness: _readiness(ready: true),
              profile: _profile(),
              statusOptions: const [],
              canWrite: true,
              busy: false,
              onEdit: () {},
              onDelete: () {},
              onReview: () => reviewed = true,
              onPause: () {},
              onStatusChanged: (_) {},
              onOpenGitHub: () {},
              onManagePermissions: () {},
            ),
          ),
        ),
      );

      expect(find.text('Agent working'), findsNothing);
      expect(find.text('Next action unavailable'), findsNothing);
      expect(find.text('Deploy'), findsOneWidget);
      await tester.tap(find.text('Deploy'));
      expect(reviewed, isTrue);
    },
  );

  testWidgets('delete confirmation explains removal and recovery', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (context) =>
                    WorkshopTicketDeleteDialog(ticket: _ticket()),
              );
            },
            child: const Text('Open delete confirmation'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open delete confirmation'));
    await tester.pumpAndSettle();
    expect(find.text('Delete ticket #42?'), findsOneWidget);
    expect(
      find.textContaining('removed from this Software Workshop'),
      findsOneWidget,
    );
    expect(find.textContaining('GitHub issue will be closed'), findsOneWidget);
    expect(find.textContaining('added back to the Project'), findsOneWidget);

    await tester.tap(find.text('Keep ticket'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('Open delete confirmation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete ticket'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room navigation stays readable on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        WorkshopRoomRail(
          rooms: _rooms,
          selected: _rooms.first,
          onSelected: (_) {},
          onAdd: () {},
          canManage: true,
        ),
      ),
    );

    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('New room'), findsOneWidget);
    expect(find.text('Mobile app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room header summarizes concurrent agent work and elapsed time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        WorkshopRoomHeader(
          room: _rooms.first,
          project: _project,
          repository: 'acme/mobile',
          healthLabel: 'Live verified',
          healthReady: true,
          activeWorkers: 3,
          longestRunning: const Duration(hours: 2, minutes: 8),
          onRepositoryChanged: (_) {},
          onSettings: () {},
          canManage: true,
        ),
      ),
    );

    expect(
      find.text('3 agents working · longest running 2 hr 8 min'),
      findsOneWidget,
    );
  });

  testWidgets('room settings save repository and permission scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    WorkshopRoomEditData? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<WorkshopRoomEditData>(
                context: context,
                builder: (context) => WorkshopRoomDialog(
                  repositories: const ['acme/mobile', 'acme/api'],
                  projects: const [_project],
                  permissionProfiles: [_profile()],
                ),
              );
            },
            child: const Text('Open room settings'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open room settings'));
    await tester.pumpAndSettle();
    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Room name'),
    );
    expect(nameField.controller?.text, 'Product delivery');
    final permissionField = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(permissionField);
    await tester.pumpAndSettle();
    await tester.tap(permissionField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('No agent access').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Product delivery');
    expect(result?.repositories, ['acme/mobile']);
    expect(result?.permissionProfile, 'none');
    expect(tester.takeException(), isNull);
  });
}

const _project = ProjectConnection(
  id: 'project-1',
  number: 1,
  owner: 'acme',
  title: 'Product delivery',
);

const _rooms = [
  WorkshopRoomModel(
    id: 'mobile',
    name: 'Mobile app',
    color: 'violet',
    repositories: ['acme/mobile'],
    projectId: 'project-1',
    permissionProfile: 'repository-maintainer',
  ),
  WorkshopRoomModel(
    id: 'platform',
    name: 'Platform',
    color: 'cyan',
    repositories: ['acme/api'],
    projectId: 'project-1',
    permissionProfile: 'repository-maintainer',
  ),
];

WorkshopTicket _ticket({
  String status = 'Todo',
  String? statusOptionId,
  String agentRunStatus = '',
  String agentRunDetail = '',
  String agentFinalStatus = '',
  String finalPullRequestUrl = '',
  bool canDeploy = true,
  bool resultMatchesCurrentTicket = false,
}) => WorkshopTicket(
  itemId: 'item-42',
  issueId: 'issue-42',
  number: 42,
  title: 'Make agent ticket handoff obvious',
  repository: 'acme-co/example-app',
  issueState: 'OPEN',
  url: 'https://github.com/acme-co/example-app/issues/42',
  status: status,
  statusOptionId: statusOptionId ?? 'todo',
  definitionOfDone: 'Every handoff stage is visible.',
  howToTest: 'Run widget tests and complete dev QA.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: 'Keep human approval explicit.',
  structured: true,
  agentReady: false,
  canDeploy: canDeploy,
  resultMatchesCurrentTicket: resultMatchesCurrentTicket,
  agentRunStatus: agentRunStatus,
  agentRunDetail: agentRunDetail,
  agentFinalStatus: agentFinalStatus,
  finalPullRequestUrl: finalPullRequestUrl,
);

const _pullRequest = WorkshopPullRequestModel(
  repository: 'acme-co/example-app',
  number: 104,
  title: 'Agent work for #44',
  url: 'https://github.com/acme-co/example-app/pull/104',
  state: 'open',
  draft: false,
  merged: false,
  mergeable: true,
  mergeableState: 'clean',
  headRef: 'ii-os-agent/0123456789abcdef0123456789abcdef',
  headSha: '0123456789abcdef0123456789abcdef01234567',
  baseRef: 'dev',
  baseSha: '89abcdef0123456789abcdef0123456789abcdef',
);

const _conflictedPullRequest = WorkshopPullRequestModel(
  repository: 'acme-co/example-app',
  number: 104,
  title: 'Agent work for #44',
  url: 'https://github.com/acme-co/example-app/pull/104',
  state: 'open',
  draft: false,
  merged: false,
  mergeable: false,
  mergeableState: 'dirty',
  headRef: 'ii-os-agent/0123456789abcdef0123456789abcdef',
  headSha: '0123456789abcdef0123456789abcdef01234567',
  baseRef: 'dev',
  baseSha: '89abcdef0123456789abcdef0123456789abcdef',
);

const _mergedPullRequest = WorkshopPullRequestModel(
  repository: 'acme-co/example-app',
  number: 103,
  title: 'Agent work for #43',
  url: 'https://github.com/acme-co/example-app/pull/103',
  state: 'closed',
  draft: false,
  merged: true,
  mergeable: true,
  mergeableState: 'clean',
  headRef: 'ii-os-agent/dispatch',
  headSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  baseRef: 'dev',
  baseSha: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  mergeCommitSha: 'cccccccccccccccccccccccccccccccccccccccc',
  qaDeploymentState: 'in_progress',
  qaDeploymentEnvironment: 'dev',
  qaDeploymentSha: 'cccccccccccccccccccccccccccccccccccccccc',
);

const _deployedPullRequest = WorkshopPullRequestModel(
  repository: 'acme-co/example-app',
  number: 103,
  title: 'Agent work for #43',
  url: 'https://github.com/acme-co/example-app/pull/103',
  state: 'closed',
  draft: false,
  merged: true,
  mergeable: true,
  mergeableState: 'clean',
  headRef: 'ii-os-agent/dispatch',
  headSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  baseRef: 'dev',
  baseSha: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  mergeCommitSha: 'cccccccccccccccccccccccccccccccccccccccc',
  qaDeploymentState: 'success',
  qaDeploymentEnvironment: 'dev',
  qaDeploymentSha: 'cccccccccccccccccccccccccccccccccccccccc',
  qaDeploymentCoversSha: 'cccccccccccccccccccccccccccccccccccccccc',
  qaDeploymentSucceeded: true,
);

WorkshopTicketReadiness _readiness({required bool ready}) =>
    WorkshopTicketReadiness([
      WorkshopReadinessCheck(
        label: 'Ticket is ready',
        detail: ready ? 'All checks passed.' : 'Finish the brief.',
        passed: ready,
      ),
    ]);

AgentPermissionModel _profile() => AgentPermissionModel.fromJson({
  'schema_version': 2,
  'id': 'repository-maintainer',
  'version': '2026-07-19.1',
  'display_name': 'Repository maintainer',
  'description': 'May edit code and run repository tests.',
  'allowed_actions': ['Edit code', 'Run tests'],
  'denied_actions': ['Mark a ticket Done'],
  'fleet': {
    'runtime_kind': 'docker',
    'capabilities': ['auto-agent'],
  },
  'secret_injection': {'environment': 'ii-os-agent', 'bindings': []},
  'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
});

AgentPermissionModel _qwenProfile() => AgentPermissionModel.fromJson({
  ..._profile().json,
  'schema_version': 3,
  'id': 'qwen38-repository-maintainer',
  'engine': 'qwen38-local',
});

Widget _harness(Widget child) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: SafeArea(child: child)),
);
