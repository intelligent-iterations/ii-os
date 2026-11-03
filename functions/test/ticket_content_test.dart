import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/ticket_content.dart';
import 'package:test/test.dart';

void main() {
  test('round trips every required ticket category', () {
    final content = TicketContent.fromRequest({
      'definitionOfDone': '- Mobile task view renders\n- API persists fields',
      'howToTest': 'Run flutter test and complete a dev issue smoke.',
      'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
      'agent': {'ready': true},
      'context': 'Keep the public mirror read-only.',
    });

    final parsed = TicketContent.parse(content.toMarkdown());

    expect(parsed.structured, isTrue);
    expect(parsed.definitionOfDone, contains('Mobile task view renders'));
    expect(parsed.howToTest, contains('flutter test'));
    expect(parsed.permissionProfile, 'repository-maintainer');
    expect(parsed.permissionRef, 'dev');
    expect(parsed.agentReady, isTrue);
    expect(parsed.context, 'Keep the public mirror read-only.');
  });

  test('new and legacy tickets fail closed until explicitly activated', () {
    final created = TicketContent.fromRequest({
      'definitionOfDone': 'Done',
      'howToTest': 'Tested',
      'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
    });

    expect(created.agentReady, isFalse);
    expect(TicketContent.parse(created.toMarkdown()).agentReady, isFalse);
    expect(TicketContent.parse('Legacy issue body').agentReady, isFalse);
  });

  test('activation can be consumed without changing ticket requirements', () {
    final content = TicketContent.fromRequest({
      'definitionOfDone': 'Done',
      'howToTest': 'Tested',
      'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
      'agent': {'ready': true},
      'context': 'Preserve this context.',
    });

    final consumed = TicketContent.parse(
      content.withAgentReady(false).toMarkdown(),
    );

    expect(consumed.agentReady, isFalse);
    expect(consumed.definitionOfDone, content.definitionOfDone);
    expect(consumed.howToTest, content.howToTest);
    expect(consumed.permissionProfile, content.permissionProfile);
    expect(consumed.context, content.context);
  });

  test('legacy issue body is preserved as additional context', () {
    final parsed = TicketContent.parse('An older unstructured issue body.');

    expect(parsed.structured, isFalse);
    expect(parsed.permissionProfile, 'none');
    expect(parsed.context, 'An older unstructured issue body.');
  });

  test('rejects a ticket missing any required execution category', () {
    expect(
      () => TicketContent.fromRequest({
        'definitionOfDone': 'Done',
        'howToTest': '',
        'permissions': {'profile': 'none', 'ref': 'dev'},
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'ticket_field_required',
        ),
      ),
    );
  });

  test('rejects traversal in a permission profile ref', () {
    expect(
      () => TicketContent.fromRequest({
        'definitionOfDone': 'Done',
        'howToTest': 'Tested',
        'permissions': {'profile': 'safe', 'ref': '../main'},
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'ticket_permissions_invalid',
        ),
      ),
    );
  });

  test('rejects malformed explicit activation input', () {
    expect(
      () => TicketContent.fromRequest({
        'definitionOfDone': 'Done',
        'howToTest': 'Tested',
        'permissions': {'profile': 'safe', 'ref': 'dev'},
        'agent': {'ready': 'yes'},
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'ticket_agent_activation_invalid',
        ),
      ),
    );
  });
}
