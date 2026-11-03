import 'package:ii_os_functions/src/domain.dart';
import 'package:test/test.dart';

Workspace workspace({
  List<String> selected = const ['acme/app'],
  Set<String> organizationAllows = const <String>{},
  bool organizationDeclared = false,
}) => Workspace.fromData(
  'workspace-1',
  {'name': 'Project', 'repositories': selected, 'organizationId': 'org-1'},
  organizationRepositories: organizationAllows,
  organizationRepositoryBoundaryDeclared: organizationDeclared,
);

void main() {
  group('repository authorization', () {
    test('a workspace still needs the repository selected', () {
      expect(workspace().containsRepository('acme/app'), isTrue);
      expect(workspace().containsRepository('acme/other'), isFalse);
    });

    test(
      'a tenant that has declared nothing yet allows what it always did',
      () {
        // Reading empty as "allow nothing" would fail every dispatch the moment
        // the tier appeared, before anyone could configure a set.
        final ws = workspace(
          selected: ['acme/app'],
          organizationAllows: const {},
        );
        expect(ws.containsRepository('acme/app'), isTrue);
      },
    );

    test('a newly declared empty tenant set allows nothing', () {
      final ws = workspace(selected: ['acme/app'], organizationDeclared: true);

      expect(ws.containsRepository('acme/app'), isFalse);
    });

    test('the tenant set is an outer bound, not an alternative', () {
      // The regression this exists to prevent: one installation now serves
      // every workspace, so a workspace admin selecting a repository the
      // tenant never allowed must not be able to act on it.
      final ws = workspace(
        selected: ['acme/app', 'acme/secret'],
        organizationAllows: const {'acme/app'},
        organizationDeclared: true,
      );

      expect(ws.containsRepository('acme/app'), isTrue);
      expect(ws.containsRepository('acme/secret'), isFalse);
    });

    test('a tenant allowing more does not widen a workspace', () {
      final ws = workspace(
        selected: ['acme/app'],
        organizationAllows: const {'acme/app', 'acme/everything-else'},
        organizationDeclared: true,
      );

      expect(ws.containsRepository('acme/app'), isTrue);
      expect(ws.containsRepository('acme/everything-else'), isFalse);
    });

    test('neither side alone is sufficient', () {
      final ws = workspace(
        selected: ['acme/app'],
        organizationAllows: const {'acme/other'},
        organizationDeclared: true,
      );

      expect(ws.containsRepository('acme/app'), isFalse);
      expect(ws.containsRepository('acme/other'), isFalse);
    });
  });
}
