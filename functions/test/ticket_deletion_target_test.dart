import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/ticket_content.dart';
import 'package:ii_os_functions/src/ticket_deletion_target.dart';
import 'package:test/test.dart';

void main() {
  group('TicketDeletionTarget', () {
    test('matches the exact Project item, repository, and issue', () {
      final target = TicketDeletionTarget.fromProject(
        projectId: 'project-1',
        itemId: 'item-42',
        repository: 'acme/example-app',
        issueNumber: 42,
        project: _project(),
      );

      expect(target.itemId, 'item-42');
      expect(target.repository, 'acme/example-app');
      expect(target.issueNumber, 42);
      expect(target.issueOpen, isTrue);
      expect(target.content.agentReady, isFalse);
    });

    test('refuses a mismatched repository or issue number', () {
      for (final input in [
        ('acme/another-app', 42),
        ('acme/example-app', 43),
      ]) {
        expect(
          () => TicketDeletionTarget.fromProject(
            projectId: 'project-1',
            itemId: 'item-42',
            repository: input.$1,
            issueNumber: input.$2,
            project: _project(),
          ),
          throwsA(
            isA<ApiError>().having(
              (error) => error.code,
              'code',
              'ticket_changed',
            ),
          ),
        );
      }
    });

    test('requires a queued deployment to be cancelled before deletion', () {
      expect(
        () => TicketDeletionTarget.fromProject(
          projectId: 'project-1',
          itemId: 'item-42',
          repository: 'acme/example-app',
          issueNumber: 42,
          project: _project(agentReady: true),
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'ticket_agent_active',
          ),
        ),
      );
    });
  });

  test('active dispatch states require pause or completion', () {
    for (final status in const [
      'dispatching',
      'dispatched',
      'dispatched_unconfirmed',
      'workflow_dispatching',
      'workflow_bound',
      'workflow_unconfirmed',
      'fleet_submitting',
      'fleet_queued',
      'fleet_running',
      'fleet_cleaning',
      'fleet_cleaned',
    ]) {
      expect(ticketDeletionRequiresPausedAgent(status), isTrue);
    }
    for (final status in const [
      null,
      '',
      'queued',
      'dispatch_failed',
      'retry_failed',
      'workflow_stalled',
      'fleet_submission_failed',
      'worker_finalized',
    ]) {
      expect(ticketDeletionRequiresPausedAgent(status), isFalse);
    }
  });
}

Map<String, Object?> _project({bool agentReady = false}) => {
  'id': 'project-1',
  'items': {
    'nodes': [
      {
        'id': 'item-42',
        'content': {
          '__typename': 'Issue',
          'number': 42,
          'state': 'OPEN',
          'body': TicketContent(
            definitionOfDone: 'The ticket can be removed.',
            howToTest: 'Confirm it is absent from the Project.',
            permissionProfile: 'repository-maintainer',
            permissionRef: 'dev',
            context: '',
            structured: true,
            agentReady: agentReady,
          ).toMarkdown(),
          'repository': {'nameWithOwner': 'acme/example-app'},
        },
      },
    ],
  },
};
