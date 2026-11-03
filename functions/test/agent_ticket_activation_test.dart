import 'package:ii_os_functions/src/agent_ticket_activation.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/ticket_content.dart';
import 'package:test/test.dart';

void main() {
  test(
    'selected activation rejects a returned ticket from a sibling repository',
    () {
      expect(
        () => AgentTicketActivationTarget.fromProject(
          projectId: 'project-1',
          itemId: 'item-1',
          project: _project(status: 'Todo'),
          expectedRepository: 'acme-co/other-app',
        ),
        _apiError('agent_ticket_repository_mismatch'),
      );
    },
  );

  test('selected activation rejects a different returned Project', () {
    final project = _project(status: 'Todo')..['id'] = 'project-other';
    expect(
      () => AgentTicketActivationTarget.fromProject(
        projectId: 'project-1',
        itemId: 'item-1',
        project: project,
        expectedRepository: 'acme-co/example-app',
      ),
      _apiError('agent_project_mismatch'),
    );
  });
  test('parses a ready Project issue and validates activation', () {
    final target = AgentTicketActivationTarget.fromProject(
      projectId: 'project-1',
      itemId: 'item-1',
      project: _project(status: 'Todo'),
    );

    expect(target.repository, 'acme-co/example-app');
    expect(target.issueNumber, 42);
    expect(target.statusFieldId, 'status-field');
    expect(target.todoOptionId, 'todo-option');
    expect(target.ticket.agentReady, isFalse);
    expect(target.needsHumanResponse, isFalse);
    expect(target.validateActivation, returnsNormally);
  });

  test('Needs Human Input must return to Todo before the next activation', () {
    final target = AgentTicketActivationTarget.fromProject(
      projectId: 'project-1',
      itemId: 'item-1',
      project: _project(status: 'Needs Human Input'),
    );

    expect(target.needsHumanResponse, isTrue);
    expect(target.validateActivation, _apiError('agent_ticket_not_todo'));
    expect(
      () => target.validateActivation(allowRecovery: true),
      returnsNormally,
    );
  });

  test('QA failure and draft states recover through reviewed activation', () {
    for (final status in const [
      '',
      'Draft',
      'QA failed',
      'QA failed refinement',
    ]) {
      final target = _target(status: status);
      expect(target.canDeploy, isTrue, reason: status);
      expect(
        () => target.validateActivation(allowRecovery: true),
        returnsNormally,
        reason: status,
      );
    }
  });

  test(
    'an interrupted In Progress pass can be deployed from its visible action',
    () {
      for (final dispatchStatus in const [
        'approval_required',
        'approval_invalidated',
        'workflow_stalled',
        'fleet_submission_failed',
        'fleet_submission_stalled',
        'fleet_lifecycle_stalled',
        'fleet_finalization_stalled',
      ]) {
        final target = _target(status: 'In Progress');

        expect(
          () => target.validateActivation(
            allowRecovery: true,
            dispatchStatus: dispatchStatus,
          ),
          returnsNormally,
          reason: dispatchStatus,
        );
      }
    },
  );

  test('human response requirement survives pause and status rewrites', () {
    expect(
      agentActivationRequiresResponse(const {
        'status': 'revoked',
        'finalProjectStatus': 'needs_human_input',
      }),
      isTrue,
    );
    expect(
      agentActivationRequiresResponse(const {
        'status': 'active',
        'finalProjectStatus': 'todo',
      }),
      isFalse,
    );
  });

  test('a question from an older brief does not block the edited ticket', () {
    const currentDigest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(
      agentActivationRequiresResponse(const {
        'status': 'finalized',
        'finalProjectStatus': 'needs_human_input',
        'ticketBodyDigest':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      }, currentTicketBodyDigest: currentDigest),
      isFalse,
    );
    expect(
      agentActivationRequiresResponse(const {
        'status': 'finalized',
        'finalProjectStatus': 'needs_human_input',
        'ticketBodyDigest': currentDigest,
      }, currentTicketBodyDigest: currentDigest),
      isTrue,
    );
  });

  test('a reset receipt supersedes the previous agent question', () {
    const currentDigest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    expect(
      agentActivationRequiresResponse(const {
        'status': 'reset',
        'finalProjectStatus': 'needs_human_input',
        'ticketBodyDigest': currentDigest,
      }, currentTicketBodyDigest: currentDigest),
      isFalse,
    );
  });

  test('rejects non-Todo statuses and incomplete permissions', () {
    expect(
      () => _target(status: 'In Progress').validateActivation(),
      _apiError('agent_ticket_not_todo'),
    );
    expect(
      () => _target(definitionOfDone: '').validateActivation(),
      _apiError('agent_ticket_requirements_incomplete'),
    );
    expect(
      () => _target(permissionProfile: 'none').validateActivation(),
      _apiError('agent_ticket_permissions_required'),
    );
    expect(
      () => _target(permissionRef: 'feature/unreviewed').validateActivation(),
      _apiError('agent_permission_ref_unreviewed'),
    );
  });

  test('requires canonical Project Status and Todo option', () {
    final project = _project(status: 'Todo');
    project['fields'] = {'nodes': <Object?>[]};

    expect(
      () => AgentTicketActivationTarget.fromProject(
        projectId: 'project-1',
        itemId: 'item-1',
        project: project,
      ),
      _apiError('agent_project_status_invalid'),
    );
  });

  test('an archived Project item cannot enter an execution flow', () {
    final project = _project(status: 'Todo');
    final items = (project['items'] as Map<String, Object?>)['nodes'] as List;
    (items.first as Map<String, Object?>)['isArchived'] = true;

    expect(
      () => AgentTicketActivationTarget.fromProject(
        projectId: 'project-1',
        itemId: 'item-1',
        project: project,
      ),
      _apiError('agent_ticket_archived'),
    );
  });
}

AgentTicketActivationTarget _target({
  String status = 'Todo',
  String definitionOfDone = 'The change is complete.',
  String permissionProfile = 'repository-maintainer',
  String permissionRef = 'dev',
}) => AgentTicketActivationTarget.fromProject(
  projectId: 'project-1',
  itemId: 'item-1',
  project: _project(
    status: status,
    definitionOfDone: definitionOfDone,
    permissionProfile: permissionProfile,
    permissionRef: permissionRef,
  ),
);

Map<String, Object?> _project({
  required String status,
  String definitionOfDone = 'The change is complete.',
  String permissionProfile = 'repository-maintainer',
  String permissionRef = 'dev',
}) {
  final body = TicketContent(
    definitionOfDone: definitionOfDone,
    howToTest: 'Run the live verification.',
    permissionProfile: permissionProfile,
    permissionRef: permissionRef,
    context: '',
    structured: true,
  ).toMarkdown();
  return {
    'id': 'project-1',
    'fields': {
      'nodes': [
        {
          '__typename': 'ProjectV2SingleSelectField',
          'id': 'status-field',
          'name': 'Status',
          'options': [
            {'id': 'todo-option', 'name': 'Todo'},
            {'id': 'progress-option', 'name': 'In Progress'},
            {'id': 'human-option', 'name': 'Needs Human Input'},
          ],
        },
      ],
    },
    'items': {
      'nodes': [
        {
          'id': 'item-1',
          'content': {
            '__typename': 'Issue',
            'number': 42,
            'body': body,
            'state': 'OPEN',
            'url': 'https://github.com/acme-co/example-app/issues/42',
            'repository': {
              'databaseId': 123,
              'nameWithOwner': 'acme-co/example-app',
            },
          },
          'fieldValues': {
            'nodes': [
              {
                'name': status,
                'field': {'id': 'status-field', 'name': 'Status'},
              },
            ],
          },
        },
      ],
    },
  };
}

Matcher _apiError(String code) =>
    throwsA(isA<ApiError>().having((error) => error.code, 'code', code));
