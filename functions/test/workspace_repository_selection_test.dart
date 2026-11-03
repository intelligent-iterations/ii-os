import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workspace_repository_selection.dart';
import 'package:test/test.dart';

import 'github_project_access_test.dart' as fixtures;

void main() {
  final workspace = fixtures.projectWorkspace(
    resourcePermissions: {'organization_projects:read'},
    workspacePermissions: {'organization_projects:read'},
  );
  test('selection narrows only to an already granted repository', () {
    expect(
      selectedWorkspaceRepository(workspace, 'acme/product'),
      'acme/product',
    );
    expect(selectedWorkspaceRepository(workspace, null), isNull);
    for (final selected in ['acme/other', '', 123]) {
      expect(
        () => selectedWorkspaceRepository(workspace, selected),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'repository_not_allowed',
          ),
        ),
      );
    }
  });
  test(
    'selected status write rejects a spoofed item without requiring agent fields',
    () {
      final project = <String, Object?>{
        'id': 'project-1',
        'items': {
          'nodes': [
            {
              'id': 'item-1',
              'content': {
                'repository': {'nameWithOwner': 'acme/product'},
              },
            },
          ],
        },
      };
      expect(
        () => requireSelectedProjectItemRepository(
          project: project,
          projectId: 'project-1',
          itemId: 'item-1',
          repository: 'acme/product',
        ),
        returnsNormally,
      );
      for (final repository in ['acme/other']) {
        expect(
          () => requireSelectedProjectItemRepository(
            project: project,
            projectId: 'project-1',
            itemId: 'item-1',
            repository: repository,
          ),
          throwsA(
            isA<ApiError>().having(
              (e) => e.code,
              'code',
              'agent_ticket_repository_mismatch',
            ),
          ),
        );
      }
      expect(
        () => requireSelectedProjectItemRepository(
          project: project,
          projectId: 'project-other',
          itemId: 'item-1',
          repository: 'acme/product',
        ),
        throwsA(isA<ApiError>()),
      );
    },
  );
}
