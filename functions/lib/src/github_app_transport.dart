import 'dart:async';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'domain.dart';

part 'github_app_discovery.dart';
part 'github_installation_scope.dart';

const String githubApiVersion = '2026-03-10';

final class GitHubAppIdentity {
  const GitHubAppIdentity({
    required this.slug,
    required this.ownerLogin,
    required this.ownerType,
  });

  final String slug;
  final String ownerLogin;
  final String ownerType;

  String get permissionSettingsUrl {
    final path = ownerType == 'Organization'
        ? '/organizations/$ownerLogin/settings/apps/$slug/permissions'
        : '/settings/apps/$slug/permissions';
    return Uri.https('github.com', path).toString();
  }
}

/// The account an App is installed on, which owns the accept-or-decline page.
///
/// This is not always the account that owns the App: a partner installs their
/// own App on their own org, and a permission update is accepted by the
/// installing account, never by the App's developer.
final class GitHubInstallationIdentity {
  const GitHubInstallationIdentity({
    required this.installationId,
    required this.accountLogin,
    required this.accountType,
  });

  final int installationId;
  final String accountLogin;
  final String accountType;

  /// Where an owner accepts an App permission update GitHub is holding.
  String get permissionUpdateUrl {
    final path = accountType == 'Organization'
        ? '/organizations/$accountLogin/settings/installations/$installationId/permissions/update'
        : '/settings/installations/$installationId/permissions/update';
    return Uri.https('github.com', path).toString();
  }
}

final class GitHubAppTransport {
  GitHubAppTransport({
    required this.appId,
    required this.privateKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String appId;
  final String privateKey;
  final http.Client _http;
  final Map<String, _CachedToken> _tokens = {};

  void close() => _http.close();

  Future<Object?> rest(
    Workspace workspace,
    String method,
    String path, {
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final token = (await _installationAccess(
      workspace,
      repository: githubRepositoryFromRestPath(path),
    )).token;
    return _restWithToken(token, method, path, body: body, timeout: timeout);
  }

  Future<Object?> _restWithToken(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 25),
    int? maximumResponseBytes,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final request = http.Request(
      method,
      Uri.parse('https://api.github.com$path'),
    )..headers.addAll(_headers(token));
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http.send(request).timeout(timeout);
    final response = maximumResponseBytes == null
        ? await http.Response.fromStream(streamed)
        : await _boundedDiscoveryResponse(
            streamed,
            maximumResponseBytes,
            deadline,
          );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final notFound = response.statusCode == 404;
      throw ApiError(
        notFound ? 404 : 502,
        notFound ? 'github_resource_not_found' : 'github_request_failed',
        _githubErrorMessage(decoded, response.statusCode),
        details: {'githubStatus': response.statusCode},
      );
    }
    return decoded;
  }

  Future<Map<String, Object?>> graphql(
    Workspace workspace,
    String query,
    Map<String, Object?> variables, {
    String? repository,
  }) async {
    final token = (await _installationAccess(
      workspace,
      repository: repository,
    )).token;
    final response = await _http
        .post(
          Uri.parse('https://api.github.com/graphql'),
          headers: _headers(token),
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 25));
    final decoded = _decode(response.body);
    if (decoded is! Map<String, Object?> ||
        response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['errors'] != null) {
      throw ApiError(
        502,
        'github_graphql_failed',
        'GitHub could not complete the request.',
        details: {'githubStatus': response.statusCode},
        diagnostic: githubGraphqlDiagnostic(
          decoded is Map<String, Object?> ? decoded['errors'] : null,
          statusCode: response.statusCode,
        ),
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid project data.',
      );
    }
    return data;
  }

  /// Permissions GitHub granted this installation.
  ///
  /// A cached installation token carries the permission set that was granted
  /// when it was issued, so it keeps reporting the old set for up to an hour
  /// after an owner approves a permission update. Pass [refresh] wherever the
  /// caller is answering "what is granted right now" rather than merely
  /// guarding a call it is about to make.
  Future<Map<String, String>> installationPermissions(
    Workspace workspace, {
    bool refresh = false,
    String? repository,
  }) async => (await _installationAccess(
    workspace,
    refresh: refresh,
    repository: repository,
  )).permissions;

  /// The full permission set currently granted to the installation.
  ///
  /// Ordinary workspace calls must use [_installationAccess], which narrows
  /// the token to the workspace grant. Legacy promotion is different: it is
  /// discovering the organization ceiling that the old unscoped workspace
  /// already used, so it deliberately omits a workspace token body here.
  Future<Map<String, String>> grantedInstallationPermissions(
    Workspace workspace,
  ) async => (await _requestInstallationAccess(workspace)).permissions;

  Future<GitHubAppIdentity> appIdentity() async {
    if (appId.isEmpty || privateKey.isEmpty) {
      throw const ApiError(
        503,
        'github_not_configured',
        'The GitHub App is not configured.',
      );
    }
    final response = await _restWithToken(_signedAppJwt(), 'GET', '/app');
    if (response is! Map<String, Object?>) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid App identity.',
      );
    }
    final responseId = response['id'];
    final slug = response['slug'];
    final owner = response['owner'];
    final ownerLogin = owner is Map<String, Object?> ? owner['login'] : null;
    final ownerType = owner is Map<String, Object?> ? owner['type'] : null;
    if (responseId is! num ||
        responseId.toInt().toString() != appId ||
        slug is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,99}$').hasMatch(slug) ||
        ownerLogin is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,99}$').hasMatch(ownerLogin) ||
        ownerType is! String ||
        !const {'Organization', 'User'}.contains(ownerType)) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an unexpected App identity.',
      );
    }
    return GitHubAppIdentity(
      slug: slug,
      ownerLogin: ownerLogin,
      ownerType: ownerType,
    );
  }

  Future<String> appBotLogin() async => '${(await appIdentity()).slug}[bot]';

  /// Permissions the App itself declares, before any installation accepts them.
  Future<Map<String, String>> appPermissions() async {
    if (appId.isEmpty || privateKey.isEmpty) {
      throw const ApiError(
        503,
        'github_not_configured',
        'The GitHub App is not configured.',
      );
    }
    final response = await _restWithToken(_signedAppJwt(), 'GET', '/app');
    final permissions = response is Map<String, Object?>
        ? response['permissions']
        : null;
    if (permissions is! Map) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid App permission set.',
      );
    }
    return permissions.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  /// The account this workspace's installation lives on.
  Future<GitHubInstallationIdentity> installationIdentity(
    Workspace workspace,
  ) async {
    final installationId = workspace.githubInstallationId;
    if (installationId == null || appId.isEmpty || privateKey.isEmpty) {
      throw const ApiError(
        503,
        'github_not_configured',
        'The GitHub App installation is not configured for this workspace.',
      );
    }
    final response = await _restWithToken(
      _signedAppJwt(),
      'GET',
      '/app/installations/$installationId',
    );
    final account = response is Map<String, Object?>
        ? response['account']
        : null;
    final login = account is Map<String, Object?> ? account['login'] : null;
    final type = account is Map<String, Object?> ? account['type'] : null;
    if (login is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,99}$').hasMatch(login) ||
        type is! String ||
        !const {'Organization', 'User'}.contains(type)) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an unexpected installation account.',
      );
    }
    return GitHubInstallationIdentity(
      installationId: installationId,
      accountLogin: login,
      accountType: type,
    );
  }

  Future<GitHubInstallationToken> issueRepositorySecretWriterToken(
    Workspace workspace, {
    required String repository,
    required int repositoryId,
  }) async {
    if (workspace.resourceGrantsExplicit &&
        !workspace.allowsGitHubPermission(
          'secrets:write',
          repository: repository,
        )) {
      throw const ApiError(
        403,
        'workspace_github_permission_required',
        'This workspace was not granted GitHub Secrets write permission for this repository.',
      );
    }
    final access = await _repositorySecretsAccess(
      workspace,
      repository: repository,
      repositoryId: repositoryId,
    );
    return GitHubInstallationToken(
      token: access.token,
      expiresAt: access.expiresAt,
    );
  }

  Future<GitHubInstallationToken> issueRepositoryContentsWriterToken(
    Workspace workspace, {
    required String repository,
    required int repositoryId,
  }) async {
    if (workspace.usesOrganizationResourceGrants &&
        !workspace.allowsGitHubPermission(
          'contents:write',
          repository: repository,
        )) {
      throw const ApiError(
        403,
        'workspace_github_permission_required',
        'This workspace was not granted Contents write permission for this repository.',
      );
    }
    if (repositoryId <= 0) {
      throw const ApiError(
        400,
        'github_repository_invalid',
        'The GitHub repository ID is invalid.',
      );
    }
    final access = await _requestInstallationAccess(
      workspace,
      body: {
        'repository_ids': [repositoryId],
        'permissions': {'contents': 'write'},
      },
    );
    if (access.permissions['contents'] != 'write' ||
        access.permissions.keys.any(
          (permission) => !const {'contents', 'metadata'}.contains(permission),
        )) {
      throw const ApiError(
        409,
        'github_contents_permission_required',
        'The GitHub App must have Contents read and write permission.',
      );
    }
    final exact = await _restWithToken(
      access.token,
      'GET',
      '/repositories/$repositoryId',
    );
    if (exact is! Map<String, Object?> ||
        exact['id'] != repositoryId ||
        exact['full_name'] != repository) {
      throw const ApiError(
        409,
        'github_repository_invalid',
        'The GitHub App token was not bound to the requested repository.',
      );
    }
    return GitHubInstallationToken(
      token: access.token,
      expiresAt: access.expiresAt,
    );
  }

  Future<_CachedToken> _repositorySecretsAccess(
    Workspace workspace, {
    required String repository,
    required int repositoryId,
  }) async {
    if (repositoryId <= 0) {
      throw const ApiError(
        400,
        'github_repository_invalid',
        'The GitHub repository ID is invalid.',
      );
    }
    final access = await _requestInstallationAccess(
      workspace,
      body: {
        'repository_ids': [repositoryId],
        'permissions': {'secrets': 'write'},
      },
    );
    if (access.permissions['secrets'] != 'write' ||
        access.permissions.keys.any(
          (permission) => !const {'metadata', 'secrets'}.contains(permission),
        )) {
      throw const ApiError(
        409,
        'github_secrets_permission_required',
        'The GitHub App must have Secrets read and write permission.',
      );
    }
    final exact = await _restWithToken(
      access.token,
      'GET',
      '/repositories/$repositoryId',
    );
    if (exact is! Map<String, Object?> ||
        exact['id'] != repositoryId ||
        exact['full_name'] != repository) {
      throw const ApiError(
        409,
        'github_repository_invalid',
        'The GitHub App token was not bound to the requested repository.',
      );
    }
    return access;
  }

  Future<_CachedToken> _installationAccess(
    Workspace workspace, {
    bool refresh = false,
    String? repository,
  }) async {
    final installationId = workspace.githubInstallationId;
    if (installationId == null || appId.isEmpty || privateKey.isEmpty) {
      throw const ApiError(
        503,
        'github_not_configured',
        'The GitHub App installation is not configured for this workspace.',
      );
    }
    final cacheKey = githubInstallationAccessCacheKey(
      workspace,
      repository: repository,
    );
    final cached = _tokens[cacheKey];
    if (installationTokenReusable(
      expiresAt: cached?.expiresAt,
      now: DateTime.now().toUtc(),
      refresh: refresh,
    )) {
      return cached!;
    }

    final access = await _requestInstallationAccess(
      workspace,
      body: githubInstallationAccessRequestBody(
        workspace,
        repository: repository,
      ),
    );
    _tokens[cacheKey] = access;
    return access;
  }

  Future<_CachedToken> _requestInstallationAccess(
    Workspace workspace, {
    Map<String, Object?>? body,
  }) async {
    final installationId = workspace.githubInstallationId;
    if (installationId == null || appId.isEmpty || privateKey.isEmpty) {
      throw const ApiError(
        503,
        'github_not_configured',
        'The GitHub App installation is not configured for this workspace.',
      );
    }
    final jwt = _signedAppJwt();
    final response = await _http
        .post(
          Uri.parse(
            'https://api.github.com/app/installations/$installationId/access_tokens',
          ),
          headers: {
            'accept': 'application/vnd.github+json',
            'authorization': 'Bearer $jwt',
            'content-type': 'application/json',
            'x-github-api-version': githubApiVersion,
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = _decode(response.body);
    if (response.statusCode != 201 || decoded is! Map<String, Object?>) {
      throw ApiError(
        502,
        'github_auth_failed',
        _githubErrorMessage(decoded, response.statusCode),
        details: {'githubStatus': response.statusCode},
      );
    }
    final token = decoded['token'];
    final expiresAt = decoded['expires_at'];
    final permissions = decoded['permissions'];
    if (token is! String || expiresAt is! String) {
      throw const ApiError(
        502,
        'github_auth_failed',
        'GitHub returned an invalid App token.',
      );
    }
    return _CachedToken(
      token,
      DateTime.parse(expiresAt).toUtc(),
      permissions is Map
          ? permissions.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  String _signedAppJwt() {
    final now = DateTime.now().toUtc();
    return JWT({
      'iat':
          now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch ~/
          1000,
      'exp': now.add(const Duration(minutes: 9)).millisecondsSinceEpoch ~/ 1000,
      'iss': appId,
    }).sign(
      RSAPrivateKey(privateKey),
      algorithm: JWTAlgorithm.RS256,
      noIssueAt: true,
    );
  }

  Map<String, String> _headers(String token) => {
    'accept': 'application/vnd.github+json',
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
    'x-github-api-version': githubApiVersion,
  };
}

Object? _decode(String body) {
  if (body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } on FormatException {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned an invalid response.',
    );
  }
}

String _githubErrorMessage(Object? response, int statusCode) {
  if (response is Map<String, Object?> && response['message'] is String) {
    return 'GitHub rejected the request: ${response['message']}';
  }
  return 'GitHub rejected the request with status $statusCode.';
}

String githubGraphqlDiagnostic(Object? errors, {required int statusCode}) {
  final summaries = <String>[];
  if (errors is List) {
    for (final error in errors.whereType<Map<Object?, Object?>>().take(3)) {
      final type = error['type']?.toString().trim() ?? '';
      final message = error['message']?.toString().trim() ?? '';
      final path = error['path'];
      final pathText = path is List
          ? path.map((part) => part.toString()).join('.')
          : '';
      final parts = [
        if (type.isNotEmpty) type,
        if (pathText.isNotEmpty) pathText,
        if (message.isNotEmpty) message,
      ];
      if (parts.isNotEmpty) summaries.add(parts.join(' | '));
    }
  }
  final detail = summaries.isEmpty
      ? 'no structured GraphQL error detail'
      : summaries.join('; ');
  final result = 'GitHub GraphQL returned status $statusCode: $detail';
  return result.length <= 1200 ? result : '${result.substring(0, 1197)}...';
}
