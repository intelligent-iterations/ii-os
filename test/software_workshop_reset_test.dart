import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/workshop_ticket.dart';
import 'package:ii_os/screens/software_workshop_ticket_widgets.dart';
import 'package:ii_os/screens/workshop_ticket_reset_dialog.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('an inactive corrupt ticket exposes the explicit reset action', (
    tester,
  ) async {
    var reset = false;
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: WorkshopTicketDetail(
            ticket: _ticket,
            readiness: _readiness,
            profile: null,
            statusOptions: const [],
            canWrite: true,
            busy: false,
            onEdit: () {},
            onDelete: () {},
            onReset: () => reset = true,
            onReview: () {},
            onPause: () {},
            onStatusChanged: (_) {},
            onOpenGitHub: () {},
            onManagePermissions: () {},
          ),
        ),
      ),
    );

    expect(find.text('Reset ticket'), findsOneWidget);
    await tester.tap(find.text('Reset ticket'));
    expect(reset, isTrue);
  });

  testWidgets('reset confirmation promises preservation before proceeding', (
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
                    const WorkshopTicketResetDialog(ticket: _ticket),
              );
            },
            child: const Text('Open reset'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reset'));
    await tester.pumpAndSettle();
    expect(find.text('Reset ticket #42?'), findsOneWidget);
    expect(find.textContaining('returns to Draft'), findsOneWidget);
    expect(
      find.textContaining('comments, and execution history remain'),
      findsOneWidget,
    );
    expect(find.textContaining('Labels are cleared'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset ticket'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}

const _ticket = WorkshopTicket(
  itemId: 'item-42',
  issueId: 'issue-42',
  number: 42,
  title: 'Recover the Workshop flow',
  repository: 'acme-co/example-app',
  issueState: 'OPEN',
  url: 'https://github.com/acme-co/example-app/issues/42',
  status: 'In Progress',
  statusOptionId: 'progress',
  definitionOfDone: 'The ticket is deployable again.',
  howToTest: 'Reset and deploy it from the Workshop.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: '',
  structured: true,
  agentReady: false,
  canDeploy: false,
  canReset: true,
);

const _readiness = WorkshopTicketReadiness([
  WorkshopReadinessCheck(
    label: 'Ticket is ready',
    detail: 'All checks passed.',
    passed: true,
  ),
]);

Widget _harness(Widget child) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: SafeArea(child: child)),
);
