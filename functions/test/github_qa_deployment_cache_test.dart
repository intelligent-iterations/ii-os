import 'dart:async';

import 'package:ii_os_functions/src/github_qa_deployment_cache.dart';
import 'package:test/test.dart';

void main() {
  const firstKey = GitHubQaDeploymentCacheKey(
    workspaceId: 'workspace-a',
    installationId: 42,
    repository: 'acme/example',
    mergeCommitSha: '89abcdef0123456789abcdef0123456789abcdef',
  );

  test('reuses one tenant-bound proof until its TTL expires', () async {
    var now = DateTime.utc(2026, 8, 26, 12);
    var loads = 0;
    final cache = GitHubQaDeploymentCache(
      ttl: const Duration(minutes: 5),
      clock: () => now,
    );
    Future<Map<String, Object?>> load() async {
      loads += 1;
      return {'deploymentId': loads};
    }

    expect(await cache.resolve(firstKey, load), {'deploymentId': 1});
    expect(await cache.resolve(firstKey, load), {'deploymentId': 1});
    expect(loads, 1);

    now = now.add(const Duration(minutes: 5));
    expect(await cache.resolve(firstKey, load), {'deploymentId': 2});
    expect(loads, 2);
  });

  test(
    'collapses concurrent loads and isolates workspace identities',
    () async {
      final cache = GitHubQaDeploymentCache();
      final pending = Completer<Map<String, Object?>>();
      var loads = 0;
      Future<Map<String, Object?>> load() {
        loads += 1;
        return pending.future;
      }

      final first = cache.resolve(firstKey, load);
      final duplicate = cache.resolve(firstKey, load);
      expect(loads, 1);

      pending.complete(const {'deploymentId': 7});
      expect(await Future.wait([first, duplicate]), [
        {'deploymentId': 7},
        {'deploymentId': 7},
      ]);

      const otherWorkspace = GitHubQaDeploymentCacheKey(
        workspaceId: 'workspace-b',
        installationId: 42,
        repository: 'acme/example',
        mergeCommitSha: '89abcdef0123456789abcdef0123456789abcdef',
      );
      expect(
        await cache.resolve(otherWorkspace, () async => {'deploymentId': 8}),
        {'deploymentId': 8},
      );
    },
  );

  test(
    'evicts the least recently used proof at the hard entry ceiling',
    () async {
      final cache = GitHubQaDeploymentCache(maxEntries: 2);
      const secondKey = GitHubQaDeploymentCacheKey(
        workspaceId: 'workspace-a',
        installationId: 42,
        repository: 'acme/example',
        mergeCommitSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      const thirdKey = GitHubQaDeploymentCacheKey(
        workspaceId: 'workspace-a',
        installationId: 42,
        repository: 'acme/example',
        mergeCommitSha: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      var firstLoads = 0;
      var secondLoads = 0;

      await cache.resolve(firstKey, () async => {'id': ++firstLoads});
      await cache.resolve(secondKey, () async => {'id': ++secondLoads});
      await cache.resolve(firstKey, () async => {'id': ++firstLoads});
      await cache.resolve(thirdKey, () async => const {'id': 3});
      await cache.resolve(firstKey, () async => {'id': ++firstLoads});
      await cache.resolve(secondKey, () async => {'id': ++secondLoads});

      expect(firstLoads, 1);
      expect(secondLoads, 2);
    },
  );
}
