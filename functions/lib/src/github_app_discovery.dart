part of 'github_app_transport.dart';

final class GitHubInstallationDiscovery {
  const GitHubInstallationDiscovery({
    required this.installationId,
    required this.repositories,
    required this.permissions,
  });

  final int installationId;
  final Set<String> repositories;
  final Map<String, String> permissions;
}

extension GitHubAppDiscovery on GitHubAppTransport {
  /// Refresh one existing installation without enumerating sibling Apps.
  Future<GitHubInstallationDiscovery> discoverInstallation(
    int installationId,
  ) async {
    if (installationId <= 0) {
      throw const ApiError(
        400,
        'invalid_installation',
        'Invalid GitHub installation.',
      );
    }
    final discovery = await _discoverInstallation(
      installationId,
      timeout: const Duration(seconds: 5),
      maximumTokenBytes: 64 * 1024,
      maximumPageBytes: 2 * 1024 * 1024,
    );
    if (discovery.repositories.isEmpty) {
      throw const ApiError(
        409,
        'github_installation_empty',
        'The GitHub installation has no accepted repositories.',
      );
    }
    return discovery;
  }

  /// Bounded App installation discovery for organization bootstrap.
  Future<List<GitHubInstallationDiscovery>> discoverInstallations() async {
    if (appId.isEmpty || privateKey.isEmpty) {
      throw const ApiError(
        503,
        'github_not_configured',
        'The GitHub App is not configured.',
      );
    }
    final response = await _restWithToken(
      _signedAppJwt(),
      'GET',
      '/app/installations?per_page=21',
    );
    if (response is! List<Object?> || response.length > 20) {
      throw const ApiError(
        409,
        'github_installation_discovery_too_large',
        'Narrow this GitHub App to no more than 20 installations.',
      );
    }
    final ids = response
        .map((value) => value is Map ? (value['id'] as num?)?.toInt() ?? 0 : 0)
        .where((value) => value > 0)
        .toList();
    if (ids.length != response.length) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid installation list.',
      );
    }
    return Future.wait(ids.map(_discoverInstallation));
  }

  Future<GitHubInstallationDiscovery> _discoverInstallation(
    int installationId, {
    Duration timeout = const Duration(seconds: 25),
    int? maximumTokenBytes,
    int? maximumPageBytes,
  }) async {
    final access = await _restWithToken(
      _signedAppJwt(),
      'POST',
      '/app/installations/$installationId/access_tokens',
      timeout: timeout,
      maximumResponseBytes: maximumTokenBytes,
    );
    final token = access is Map ? access['token'] : null;
    final rawPermissions = access is Map ? access['permissions'] : null;
    if (token is! String || token.isEmpty || rawPermissions is! Map) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid installation authorization.',
      );
    }
    final repositories = <String>{};
    var page = 1;
    int? total;
    while (page <= 5) {
      final response = await _restWithToken(
        token,
        'GET',
        '/installation/repositories?per_page=100&page=$page',
        timeout: timeout,
        maximumResponseBytes: maximumPageBytes,
      );
      final values = response is Map ? response['repositories'] : null;
      final count = response is Map ? response['total_count'] : null;
      if (values is! List<Object?> ||
          values.length > 100 ||
          count is! int ||
          count < 0 ||
          count > 500) {
        throw const ApiError(
          409,
          'github_repository_discovery_too_large',
          'Narrow this GitHub App installation to no more than 500 repositories.',
        );
      }
      total ??= count;
      if (count != total) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub repository discovery changed while paging.',
        );
      }
      for (final value in values) {
        final fullName = value is Map ? value['full_name'] : null;
        if (fullName is! String ||
            !_discoveredRepositoryName.hasMatch(fullName) ||
            !repositories.add(fullName)) {
          throw const ApiError(
            502,
            'github_response_invalid',
            'GitHub returned an invalid repository list.',
          );
        }
      }
      if (repositories.length >= total) break;
      page += 1;
    }
    if (repositories.length != total) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub repository discovery was incomplete.',
      );
    }
    return GitHubInstallationDiscovery(
      installationId: installationId,
      repositories: repositories,
      permissions: rawPermissions.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }
}

final _discoveredRepositoryName = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$',
);

Future<http.Response> _boundedDiscoveryResponse(
  http.StreamedResponse response,
  int maximumBytes,
  DateTime deadline,
) async {
  final reader = StreamIterator(response.stream);
  final bytes = <int>[];
  try {
    if ((response.contentLength ?? 0) > maximumBytes) {
      throw const ApiError(
        502,
        'github_response_too_large',
        'GitHub discovery response exceeds its limit.',
      );
    }
    while (await reader.moveNext().timeout(
      deadline.difference(DateTime.now()),
    )) {
      if (bytes.length + reader.current.length > maximumBytes) {
        throw const ApiError(
          502,
          'github_response_too_large',
          'GitHub discovery response exceeds its limit.',
        );
      }
      bytes.addAll(reader.current);
    }
    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
    );
  } finally {
    await reader.cancel();
  }
}
