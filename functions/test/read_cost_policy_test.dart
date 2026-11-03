import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/read_cost_policy.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('rejects a stale client before a formerly polled read route', () {
    final request = Request('GET', Uri.parse('https://ii-os.test/api'));

    expect(
      () => requireExplicitReadPolicyForRead(request, const [
        'v1',
        'workspaces',
        'workspace-1',
        'jobs',
      ]),
      throwsA(
        isA<ApiError>()
            .having((error) => error.status, 'status', 428)
            .having(
              (error) => error.code,
              'code',
              'explicit_read_policy_required',
            ),
      ),
    );
  });

  test('accepts the explicit read client and does not gate mutations', () {
    final current = Request(
      'GET',
      Uri.parse('https://ii-os.test/api'),
      headers: {explicitReadPolicyHeader: explicitReadPolicyVersion},
    );
    final mutation = Request('POST', Uri.parse('https://ii-os.test/api'));

    expect(
      () => requireExplicitReadPolicyForRead(current, const [
        'v1',
        'notifications',
      ]),
      returnsNormally,
    );
    expect(
      () => requireExplicitReadPolicyForRead(mutation, const [
        'v1',
        'notifications',
      ]),
      returnsNormally,
    );
  });

  test('gates organization people and member-access reads', () {
    final request = Request('GET', Uri.parse('https://ii-os.test/api'));

    for (final path in [
      const ['v1', 'organizations', 'organization-1', 'people'],
      const [
        'v1',
        'organizations',
        'organization-1',
        'members',
        'user-1',
        'workspaces',
      ],
    ]) {
      expect(
        () => requireExplicitReadPolicyForRead(request, path),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'explicit_read_policy_required',
          ),
        ),
      );
    }
  });
}
