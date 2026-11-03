import 'package:ii_os_functions/src/codex_auth_store.dart';
import 'package:ii_os_functions/src/workspace_store.dart';
import 'package:test/test.dart';

import 'support/credential_firestore_fake.dart';

void main() {
  test(
    'another workspace reads the latest repository credential digest',
    () async {
      final firestore = CredentialFirestoreFake();
      firestore.documents['workspaces/workspace-b/codexAuth/example~project'] =
          {
            'repository': 'example/project',
            'repositoryId': 123,
            'status': 'valid',
            'secretDigest': 'a' * 64,
          };
      firestore
          .documents['codexCredentialBindings/github.com~123~CODEX_AUTH_JSON'] = {
        'repository': 'example/project',
        'repositoryId': 123,
        'status': 'valid',
        'secretDigest': 'b' * 64,
      };
      final state = await CodexAuthStore(
        store: WorkspaceStore(firestore),
      ).repositoryState('workspace-b', 'example/project');
      expect(state?['secretDigest'], 'b' * 64);
      expect(firestore.reads, lessThanOrEqualTo(2));
    },
  );
}
