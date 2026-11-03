import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';

void main() {
  test('linked project discovery keeps bounded open project choices', () {
    final projects = parseLinkedGitHubProjects({
      'repository': {
        'projectsV2': {
          'nodes': [
            {
              'id': 'PVT_delivery',
              'number': 7,
              'title': 'Delivery',
              'url': 'https://github.com/orgs/acme/projects/7',
              'closed': false,
            },
            {
              'id': 'PVT_closed',
              'number': 3,
              'title': 'Old plan',
              'url': 'https://github.com/orgs/acme/projects/3',
              'closed': true,
            },
            {'id': '', 'number': 0, 'title': ''},
          ],
        },
      },
    }, owner: 'acme');

    expect(projects, hasLength(1));
    expect(projects.single.id, 'PVT_delivery');
    expect(projects.single.number, 7);
    expect(projects.single.owner, 'acme');
    expect(projects.single.title, 'Delivery');
  });

  test('linked project discovery rejects an unreadable GitHub response', () {
    expect(
      () => parseLinkedGitHubProjects(const {}, owner: 'acme'),
      throwsA(isA<ApiError>()),
    );
  });
}
