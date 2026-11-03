@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_permission.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/workshop_room.dart';
import 'package:ii_os/models/workshop_ticket.dart';
import 'package:ii_os/screens/software_workshop_rooms.dart';
import 'package:ii_os/screens/software_workshop_ticket_widgets.dart';
import 'package:ii_os/screens/ticket_dialog.dart';
import 'package:ii_os/screens/workshop_ticket_review_dialog.dart';

import 'golden_harness.dart';

void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('room and pending-task hierarchy', (tester) async {
    tester.view.physicalSize = const Size(980, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      goldenHarness(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkshopRoomRail(
              rooms: _rooms,
              selected: _rooms.first,
              onSelected: (_) {},
              onAdd: () {},
              canManage: true,
            ),
            const SizedBox(height: 16),
            WorkshopRoomHeader(
              room: _rooms.first,
              project: _project,
              repository: 'acme/mobile',
              healthLabel: 'Live verified',
              healthReady: true,
              activeWorkers: 2,
              longestRunning: const Duration(minutes: 37),
              onRepositoryChanged: (_) {},
              onSettings: () {},
              canManage: true,
            ),
            const SizedBox(height: 16),
            WorkshopTaskFilterBar(
              selected: WorkshopFilter.active,
              counts: const {
                WorkshopFilter.active: 4,
                WorkshopFilter.attention: 1,
                WorkshopFilter.working: 2,
                WorkshopFilter.qa: 1,
                WorkshopFilter.done: 12,
              },
              onSelected: (_) {},
              onRefresh: () {},
              refreshing: false,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) => WorkshopTicketListCard(
                ticket: _ticket,
                selected: true,
                accentColor: workshopRoomColor(context, 'violet'),
                onSelected: () {},
              ),
            ),
          ],
        ),
        width: 940,
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/software_workshop_rooms.png'),
    );
  });

  testWidgets('Ready for QA has one clear handoff', (tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      goldenHarness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _qaTicket,
            readiness: const WorkshopTicketReadiness([
              WorkshopReadinessCheck(
                label: 'Ticket is in Todo',
                detail: 'Move this ticket to Todo before deploying it.',
                passed: false,
              ),
            ]),
            profile: _profile,
            statusOptions: const [
              {'id': 'qa', 'name': 'Ready for QA'},
              {'id': 'done', 'name': 'Done'},
              {'id': 'failed', 'name': 'QA failed'},
            ],
            canWrite: true,
            busy: false,
            onEdit: _ignore,
            onDelete: _ignore,
            onReview: _ignore,
            onPause: _ignore,
            onStatusChanged: _ignoreString,
            onOpenGitHub: _ignore,
            onManagePermissions: _ignore,
          ),
        ),
        width: 720,
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/workshop_ticket_ready_for_qa.png'),
    );
  });

  testWidgets('ticket creation offers local Qwen without workflow status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      goldenHarness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<TicketEditData>(
              context: context,
              builder: (context) => TicketDialog(
                heading: 'Create workshop ticket',
                repository: 'acme-co/example-app',
                projectId: _project.id,
                projects: const [_project],
                permissionProfiles: [_profile, _qwenProfile],
              ),
            ),
            child: const Text('Create ticket'),
          ),
        ),
        width: 720,
      ),
    );
    await tester.tap(find.text('Create ticket'));
    await tester.pumpAndSettle();
    final selectedEngine = find.text('Repository maintainer · Codex').last;
    await tester.ensureVisible(selectedEngine);
    await tester.tap(selectedEngine);
    await tester.pumpAndSettle();

    expect(find.text('Repository maintainer · Qwen3.8 local'), findsOneWidget);
    expect(find.text('Status'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/workshop_ticket_qwen_engine.png'),
    );
  });

  testWidgets('deployment review offers Qwen before the pass is deployed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      goldenHarness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<WorkshopTicketReviewResult>(
              context: context,
              builder: (context) => WorkshopTicketReviewDialog(
                ticket: _ticket,
                readiness: const WorkshopTicketReadiness([
                  WorkshopReadinessCheck(
                    label: 'Ticket can be deployed',
                    detail: 'The selected model is ready for this pass.',
                    passed: true,
                  ),
                ]),
                profile: _profile,
                permissionProfiles: [_profile, _qwenProfile],
              ),
            ),
            child: const Text('Review deployment'),
          ),
        ),
        width: 720,
      ),
    );
    await tester.tap(find.text('Review deployment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repository maintainer · Codex').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repository maintainer · Qwen3.8 local').last);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/workshop_deployment_qwen_model.png'),
    );
  });
}

void _ignore() {}
void _ignoreString(String _) {}

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
    repositories: ['acme/mobile', 'acme/design-system'],
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

const _ticket = WorkshopTicket(
  itemId: 'item-42',
  issueId: 'issue-42',
  number: 42,
  title: 'Make pending work easier to scan',
  repository: 'acme/mobile',
  issueState: 'OPEN',
  url: 'https://github.com/acme/mobile/issues/42',
  status: 'Todo',
  statusOptionId: 'todo',
  definitionOfDone: 'Pending work is visually prioritised.',
  howToTest: 'Review the room at desktop and phone sizes.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: '',
  structured: true,
  agentReady: false,
  canDeploy: true,
);

const _qaTicket = WorkshopTicket(
  itemId: 'item-43',
  issueId: 'issue-43',
  number: 43,
  title: 'Add a play button to example media cards',
  repository: 'acme-co/example-app',
  issueState: 'OPEN',
  url: 'https://github.com/acme-co/example-app/issues/43',
  status: 'Ready for QA',
  statusOptionId: 'qa',
  definitionOfDone: 'Media cards play and pause their clip.',
  howToTest: 'Open a media card, then play, pause, and resume its clip.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: 'Keep the player keyboard accessible.',
  structured: true,
  agentReady: false,
  canDeploy: false,
  agentRunStatus: 'worker_finalized',
  agentFinalStatus: 'needs_human_input',
);

final _profile = AgentPermissionModel.fromJson({
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

final _qwenProfile = AgentPermissionModel.fromJson({
  ..._profile.json,
  'schema_version': 3,
  'engine': 'qwen38-local',
  'id': 'qwen38-repository-maintainer',
  'description': 'May edit code and run tests on a local GPU.',
});
