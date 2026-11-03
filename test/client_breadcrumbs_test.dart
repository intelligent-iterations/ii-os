import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/client_breadcrumbs.dart';

void main() {
  test('keeps a bounded, recent, query-free breadcrumb trail', () {
    var now = DateTime.utc(2026, 8, 25, 16);
    final breadcrumbs = ClientBreadcrumbs(
      capacity: 3,
      retention: const Duration(minutes: 10),
      clock: () => now,
    );

    breadcrumbs.record(
      category: 'navigation',
      name: 'route',
      route: '/workspaces/workspace-1/tickets?token=secret',
    );
    now = now.add(const Duration(minutes: 1));
    breadcrumbs.record(
      category: 'api',
      name: 'request.started',
      route: 'v1/workspaces/workspace-1/projects?projectId=secret',
      requestId: 'request-1',
    );
    now = now.add(const Duration(minutes: 1));
    breadcrumbs.record(
      category: 'api',
      name: 'request.failed',
      route: 'v1/workspaces/workspace-1/projects',
      requestId: 'request-1',
      statusCode: 502,
    );
    now = now.add(const Duration(minutes: 1));
    breadcrumbs.record(
      category: 'navigation',
      name: 'route',
      route: '/workspaces/workspace-1/home',
    );

    final snapshot = breadcrumbs.snapshot();

    expect(snapshot, hasLength(3));
    expect(snapshot.first['name'], 'request.started');
    expect(snapshot.first['route'], 'v1/workspaces/workspace-1/projects');
    expect(snapshot[1]['statusCode'], 502);
    expect(snapshot.last['route'], '/workspaces/workspace-1/home');
    expect(snapshot.toString(), isNot(contains('secret')));

    now = now.add(const Duration(minutes: 11));
    expect(breadcrumbs.snapshot(), isEmpty);
  });

  test('rejects free-form breadcrumb categories and names', () {
    final breadcrumbs = ClientBreadcrumbs();

    expect(
      () => breadcrumbs.record(category: 'prompt', name: 'user text'),
      throwsArgumentError,
    );
  });
}
