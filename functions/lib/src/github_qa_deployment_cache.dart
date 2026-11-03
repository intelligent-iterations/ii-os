typedef GitHubQaDeploymentLoader = Future<Map<String, Object?>> Function();

final class GitHubQaDeploymentCacheKey {
  const GitHubQaDeploymentCacheKey({
    required this.workspaceId,
    required this.installationId,
    required this.repository,
    required this.mergeCommitSha,
  });

  final String workspaceId;
  final int installationId;
  final String repository;
  final String mergeCommitSha;

  @override
  bool operator ==(Object other) =>
      other is GitHubQaDeploymentCacheKey &&
      other.workspaceId == workspaceId &&
      other.installationId == installationId &&
      other.repository == repository &&
      other.mergeCommitSha == mergeCommitSha;

  @override
  int get hashCode =>
      Object.hash(workspaceId, installationId, repository, mergeCommitSha);
}

/// Process-local, tenant-bound deployment proof cache.
///
/// There is no warmer or timer. A selected ticket fills one entry, concurrent
/// requests share its in-flight load, and expiration is checked only on read.
final class GitHubQaDeploymentCache {
  GitHubQaDeploymentCache({
    this.ttl = const Duration(minutes: 5),
    this.maxEntries = 256,
    DateTime Function()? clock,
  }) : assert(ttl > Duration.zero),
       assert(maxEntries > 0),
       _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _clock;
  final Map<GitHubQaDeploymentCacheKey, _GitHubQaDeploymentCacheEntry>
  _entries = {};
  final Map<GitHubQaDeploymentCacheKey, Future<Map<String, Object?>>> _pending =
      {};

  Future<Map<String, Object?>> resolve(
    GitHubQaDeploymentCacheKey key,
    GitHubQaDeploymentLoader load,
  ) {
    final cached = _entries.remove(key);
    if (cached != null && _clock().isBefore(cached.createdAt.add(ttl))) {
      _entries[key] = cached;
      return Future.value(cached.proof);
    }
    final pending = _pending[key];
    if (pending != null) return pending;

    final future = _loadAndStore(key, load);
    _pending[key] = future;
    return future.whenComplete(() {
      if (identical(_pending[key], future)) _pending.remove(key);
    });
  }

  Future<Map<String, Object?>> _loadAndStore(
    GitHubQaDeploymentCacheKey key,
    GitHubQaDeploymentLoader load,
  ) async {
    final proof = Map<String, Object?>.unmodifiable(await load());
    _entries[key] = _GitHubQaDeploymentCacheEntry(
      proof: proof,
      createdAt: _clock(),
    );
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return proof;
  }
}

final class _GitHubQaDeploymentCacheEntry {
  const _GitHubQaDeploymentCacheEntry({
    required this.proof,
    required this.createdAt,
  });

  final Map<String, Object?> proof;
  final DateTime createdAt;
}
