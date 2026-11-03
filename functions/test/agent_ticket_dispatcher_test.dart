import 'package:ii_os_functions/src/agent_ticket_dispatcher.dart';
import 'package:ii_os_functions/src/ticket_content.dart';
import 'package:test/test.dart';

void main() {
  test('direct dispatch resolves the exact open Project ticket', () {
    final body = const TicketContent(
      definitionOfDone: 'The change is complete.',
      howToTest: 'Run the live verification.',
      permissionProfile: 'repository-maintainer',
      permissionRef: 'dev',
      context: '',
      structured: true,
    ).toMarkdown();
    final todo = AgentQueueTicket.parse(
      _item('item-todo', 10, 'Todo', body),
      'status-field',
    );
    expect(todo?.repository, 'acme-co/example-app');
    expect(todo?.permissionRef, 'dev');
    expect(
      AgentQueueTicket.parse(
        _item('item-closed', 13, 'Todo', body, state: 'CLOSED'),
        'status-field',
      ),
      isNull,
    );
    expect(todo?.status, 'Todo');
  });

  test('human dispatch ids are deterministic and Project-item scoped', () {
    expect(
      humanAgentDispatchId('request-1', 'item-1'),
      humanAgentDispatchId('request-1', 'item-1'),
    );
    expect(
      humanAgentDispatchId('request-1', 'item-1'),
      isNot(humanAgentDispatchId('request-1', 'item-2')),
    );
    expect(humanAgentDispatchId('request-1', 'item-1'), startsWith('human:'));
  });

  test('workflow binding accepts only the exact human deployment run', () {
    final dispatchedAt = DateTime.utc(2026, 8, 22, 12);
    final exact = {
      'id': 7,
      'display_title': 'ii-os agent / acme-co/example-app#10 / human:claim',
      'event': 'workflow_dispatch',
      'run_attempt': 1,
      'actor': {'login': 'example-pipeline[bot]'},
      'head_branch': 'ii-os-agent-v4-source',
      'head_sha': 'source-sha',
      'path': '.github/workflows/ii-os-agent-task.yml',
      'created_at': '2026-08-22T12:00:01Z',
    };
    final wrongActor = {
      ...exact,
      'id': 8,
      'actor': {'login': 'another-user'},
    };
    final stale = {...exact, 'id': 9, 'created_at': '2026-08-22T11:58:59Z'};

    final matches = matchingHumanDeploymentWorkflowRuns(
      [exact, wrongActor, stale],
      expectedTitle: 'ii-os agent / acme-co/example-app#10 / human:claim',
      expectedActor: 'example-pipeline[bot]',
      expectedSourceRef: 'ii-os-agent-v4-source',
      expectedSourceSha: 'source-sha',
      dispatchedAt: dispatchedAt,
    );

    expect(matches.map((run) => run['id']), [7]);
  });
}

Map<String, Object?> _item(
  String itemId,
  int number,
  String status,
  String body, {
  String state = 'OPEN',
}) => {
  'id': itemId,
  'isArchived': false,
  'content': {
    '__typename': 'Issue',
    'number': number,
    'body': body,
    'state': state,
    'repository': {'databaseId': 123, 'nameWithOwner': 'acme-co/example-app'},
  },
  'fieldValues': {
    'nodes': [
      {
        '__typename': 'ProjectV2ItemFieldSingleSelectValue',
        'name': status,
        'field': {'id': 'status-field', 'name': 'Status'},
      },
    ],
  },
};
