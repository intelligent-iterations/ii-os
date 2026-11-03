import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/workshop_pull_request.dart';
import 'package:ii_os/models/workshop_ticket.dart';
import 'package:ii_os/screens/software_workshop_ticket_widgets.dart';
import 'package:ii_os/screens/workshop_ticket_review_dialog.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets(
    'failed QA can redeploy even when the previous pull request is merged',
    (tester) async {
      for (final status in const ['QA failed', 'QA failed refinement']) {
        var reviewed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: IiOsTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WorkshopTicketDetail(
                  ticket: _ticket(status),
                  readiness: const WorkshopTicketReadiness([
                    WorkshopReadinessCheck(
                      label: 'Ticket can be deployed',
                      detail: 'Deploying starts a reviewed next pass.',
                      passed: true,
                    ),
                  ]),
                  profile: null,
                  statusOptions: const [
                    {'id': 'qa', 'name': 'Ready for QA'},
                  ],
                  canWrite: true,
                  busy: false,
                  onEdit: () {},
                  onDelete: () {},
                  onReview: () => reviewed = true,
                  onPause: () {},
                  onStatusChanged: (_) {},
                  onOpenGitHub: () {},
                  onManagePermissions: () {},
                  pullRequest: _mergedPullRequest,
                ),
              ),
            ),
          ),
        );

        expect(find.text('Review & redeploy'), findsOneWidget, reason: status);
        expect(find.text('Ready for QA'), findsNothing, reason: status);
        expect(find.textContaining('Previous pass.'), findsOneWidget);
        await tester.ensureVisible(find.text('Review & redeploy'));
        await tester.tap(find.text('Review & redeploy'));
        expect(reviewed, isTrue, reason: status);
      }
    },
  );

  testWidgets('failed QA review names the next agent pass explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => WorkshopTicketReviewDialog(
                ticket: _ticket('QA failed'),
                readiness: const WorkshopTicketReadiness([
                  WorkshopReadinessCheck(
                    label: 'Ticket can be deployed',
                    detail: 'Deploying starts a reviewed next pass.',
                    passed: true,
                  ),
                ]),
                profile: null,
                permissionProfiles: const [],
              ),
            ),
            child: const Text('Review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Review and redeploy the next pass'), findsOneWidget);
    expect(find.text('Deploy next pass'), findsOneWidget);
  });

  testWidgets('conflict recovery reviews the exact editable agent prompt', (
    tester,
  ) async {
    WorkshopTicketReviewResult? approvedResult;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              approvedResult = await showDialog<WorkshopTicketReviewResult>(
                context: context,
                builder: (context) => WorkshopTicketReviewDialog(
                  ticket: _ticket('Needs Human Input'),
                  readiness: const WorkshopTicketReadiness([
                    WorkshopReadinessCheck(
                      label: 'Ticket can be deployed',
                      detail: 'Deploying starts a reviewed next pass.',
                      passed: true,
                    ),
                  ]),
                  profile: null,
                  permissionProfiles: const [],
                  conflictedPullRequest: _conflictedPullRequest,
                ),
              );
            },
            child: const Text('Resolve'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();

    expect(find.text('Review conflict-resolution pass'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains(_conflictedPullRequest.url));
    expect(field.controller!.text, contains('preserve newer work'));

    await tester.enterText(
      find.byType(TextField),
      'Resolve against latest dev and keep the responsive layout.',
    );
    await tester.tap(find.text('Deploy conflict-resolution pass'));
    await tester.pumpAndSettle();

    expect(
      approvedResult?.response,
      'Resolve against latest dev and keep the responsive layout.',
    );
    expect(approvedResult?.deploy, isTrue);
  });
}

WorkshopTicket _ticket(String status) => WorkshopTicket(
  itemId: 'item-42',
  issueId: 'issue-42',
  number: 42,
  title: 'Settings page mobile layout',
  repository: 'acme-co/example-app',
  issueState: 'OPEN',
  url: 'https://github.com/acme-co/example-app/issues/42',
  status: status,
  statusOptionId: 'qa-failed',
  definitionOfDone: 'The refined mobile layout passes QA.',
  howToTest: 'Make the browser narrow and check every settings panel.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: '',
  structured: true,
  agentReady: false,
  canDeploy: true,
  resultMatchesCurrentTicket: true,
  agentRunStatus: 'worker_finalized',
  agentFinalStatus: 'ready_for_qa',
  finalPullRequestUrl: 'https://github.com/acme-co/example-app/pull/101',
);

const _mergedPullRequest = WorkshopPullRequestModel(
  repository: 'acme-co/example-app',
  number: 101,
  title: 'Agent work for #42',
  url: 'https://github.com/acme-co/example-app/pull/101',
  state: 'closed',
  draft: false,
  merged: true,
  mergeable: true,
  mergeableState: 'clean',
  headRef: 'ii-os-agent/dispatch',
  headSha: '1111111111111111111111111111111111111111',
  baseRef: 'dev',
  baseSha: '2222222222222222222222222222222222222222',
  mergeCommitSha: '3333333333333333333333333333333333333333',
);

const _conflictedPullRequest = WorkshopPullRequestModel(
  repository: 'acme-co/example-app',
  number: 102,
  title: 'Agent work for #42',
  url: 'https://github.com/acme-co/example-app/pull/102',
  state: 'open',
  draft: false,
  merged: false,
  mergeable: false,
  mergeableState: 'dirty',
  headRef: 'ii-os-agent/conflicted-pass',
  headSha: '1111111111111111111111111111111111111111',
  baseRef: 'dev',
  baseSha: '2222222222222222222222222222222222222222',
);
