import 'package:shelf/shelf.dart';

import 'api_error.dart';

const explicitReadPolicyHeader = 'x-ii-os-read-policy';
const explicitReadPolicyVersion = 'explicit-v1';

/// Rejects old web clients on the routes that previously performed passive
/// reads. The check runs before workspace access and route-specific Firestore
/// reads, so a tab still running an older client cannot keep issuing those
/// passive reads.
void requireExplicitReadPolicyForRead(Request request, List<String> path) {
  if (!_requiresExplicitReadPolicy(request.method, path)) return;
  if (request.headers[explicitReadPolicyHeader] == explicitReadPolicyVersion) {
    return;
  }
  throw const ApiError(
    428,
    'explicit_read_policy_required',
    'Reload ii-os before refreshing this data. This older client was stopped '
        'to prevent unbounded Firestore read charges.',
  );
}

bool _requiresExplicitReadPolicy(String method, List<String> path) {
  if (method != 'GET') return false;
  if (_matches(path, const ['v1', 'notifications'])) return true;
  if (path.length == 4 &&
      path[0] == 'v1' &&
      path[1] == 'workspaces' &&
      const {'jobs', 'interactive-sessions'}.contains(path[3])) {
    return true;
  }
  if (path.length == 4 &&
      path[0] == 'v1' &&
      path[1] == 'organizations' &&
      const {'fleet', 'people'}.contains(path[3])) {
    return true;
  }
  if (path.length == 6 &&
      path[0] == 'v1' &&
      path[1] == 'organizations' &&
      path[3] == 'members' &&
      path[5] == 'workspaces') {
    return true;
  }
  return false;
}

bool _matches(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}
