import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'agent_permission_profile.dart';
import 'agent_repository_topology.dart';
import 'api_error.dart';
import 'auth_service.dart';

const githubActionsOidcIssuer = 'https://token.actions.githubusercontent.com';

final class GitHubActionsPrincipal {
  const GitHubActionsPrincipal({
    required this.repository,
    required this.repositoryId,
    required this.runId,
    required this.runAttempt,
    required this.sha,
    required this.ref,
    required this.workflowRef,
    required this.jobWorkflowRef,
    required this.actor,
    required this.subject,
    required this.environment,
  });

  final String repository;
  final int repositoryId;
  final int runId;
  final int runAttempt;
  final String sha;
  final String ref;
  final String workflowRef;
  final String jobWorkflowRef;
  final String actor;
  final String subject;
  final String environment;

  /// Rejects a verified identity that is not one of the agent workflows.
  void requireAgentWorkflowIdentity() {
    if (environment != iiOsAgentEnvironment &&
        environment != iiOsAgentBootstrapEnvironment) {
      throw _invalidOidc;
    }
  }

  String get trustedRef =>
      ref.startsWith('refs/tags/') ? ref.substring('refs/tags/'.length) : '';

  AuthenticatedUser get auditActor => AuthenticatedUser(
    uid: 'github-actions:$repository:$runId:$runAttempt',
    email: '',
    emailVerified: true,
    displayName: actor,
    isOwner: false,
  );

  bool jobUses(String workflow) {
    final expected = '$repository/.github/workflows/$workflow@$ref';
    if (workflow == iiOsAgentTaskWorkflow) {
      // The dispatched task is a thin caller. Work-ticket requests execute in
      // this exact reviewed reusable body, while `workflow_ref` retains the
      // immutable caller identity.
      final expectedBody =
          '$repository/.github/workflows/$iiOsAgentWorkTicketWorkflow@$ref';
      return workflowRef == expected && jobWorkflowRef == expectedBody;
    }
    if (workflow == iiOsAgentPermissionInstallerWorkflow) {
      // The dispatch surface is a thin caller, so the job body is the pinned
      // implementation in the coordinator repository. Authentication has
      // already bound `job_workflow_ref` to that exact body, and the caller's
      // own identity is what `workflow_ref` carries.
      return workflowRef == expected;
    }
    if (jobWorkflowRef.isNotEmpty) return jobWorkflowRef == expected;
    return const {
          iiOsAgentTaskWorkflow,
          iiOsAgentPermissionInstallerWorkflow,
        }.contains(workflow) &&
        workflowRef == expected;
  }
}

final class GitHubActionsOidcVerifier {
  GitHubActionsOidcVerifier({
    required this.audience,
    required this.agentRepositories,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? _utcNow;

  final String audience;
  final AgentRepositoryTopology agentRepositories;
  final http.Client _http;
  final DateTime Function() _clock;
  Map<String, JWTKey> _keys = const {};
  DateTime? _keysExpiresAt;

  Future<GitHubActionsPrincipal> authenticate(Request request) async {
    final authorization = request.headers['authorization'] ?? '';
    if (!authorization.startsWith('Bearer ')) throw _invalidOidc;
    return authenticateRaw(authorization.substring('Bearer '.length).trim());
  }

  Future<GitHubActionsPrincipal> authenticateRaw(String token) async {
    if (audience.isEmpty || token.length > 12000) throw _invalidOidc;
    try {
      final decoded = JWT.decode(token);
      final kid = decoded.header?['kid'];
      if (decoded.header?['alg'] != 'RS256' ||
          kid is! String ||
          !_safeKid.hasMatch(kid)) {
        throw _invalidOidc;
      }
      var key = (await _currentKeys())[kid];
      if (key == null) {
        await _refreshKeys();
        key = _keys[kid];
      }
      if (key == null) throw _invalidOidc;
      final verified = JWT.verify(
        token,
        key,
        audience: Audience.one(audience),
        issuer: githubActionsOidcIssuer,
      );
      final claims = verified.payload;
      if (claims is! Map<String, dynamic>) throw _invalidOidc;
      return githubActionsPrincipalFromClaims(
        claims,
        now: _clock(),
        agentRepositories: agentRepositories,
      );
    } on ApiError {
      rethrow;
    } on Object {
      throw _invalidOidc;
    }
  }

  Future<Map<String, JWTKey>> _currentKeys() async {
    if (_keys.isNotEmpty && _keysExpiresAt?.isAfter(_clock().toUtc()) == true) {
      return _keys;
    }
    await _refreshKeys();
    return _keys;
  }

  Future<void> _refreshKeys() async {
    final response = await _http
        .get(Uri.parse('$githubActionsOidcIssuer/.well-known/jwks'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.body.length > 100000) {
      throw _invalidOidc;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['keys'] is! List) {
      throw _invalidOidc;
    }
    final keys = <String, JWTKey>{};
    for (final item in decoded['keys'] as List) {
      if (item is! Map) continue;
      final jwk = item.cast<String, dynamic>();
      final kid = jwk['kid'];
      if (kid is String &&
          _safeKid.hasMatch(kid) &&
          jwk['kty'] == 'RSA' &&
          jwk['alg'] == 'RS256') {
        keys[kid] = JWTKey.fromJWK(jwk);
      }
    }
    if (keys.isEmpty) throw _invalidOidc;
    _keys = Map.unmodifiable(keys);
    _keysExpiresAt = _clock().toUtc().add(const Duration(minutes: 10));
  }
}

GitHubActionsPrincipal githubActionsPrincipalFromClaims(
  Map<String, dynamic> claims, {
  required DateTime now,
  required AgentRepositoryTopology agentRepositories,
}) {
  String claim(String name) {
    final value = claims[name];
    if (value is! String || value.isEmpty) throw _invalidOidc;
    return value;
  }

  int positiveIntClaim(String name) {
    final parsed = int.tryParse(claim(name));
    if (parsed == null || parsed <= 0) throw _invalidOidc;
    return parsed;
  }

  final repository = claim('repository');
  final repositoryId = positiveIntClaim('repository_id');
  final runId = positiveIntClaim('run_id');
  final runAttempt = positiveIntClaim('run_attempt');
  final sha = claim('sha');
  final ref = claim('ref');
  final workflowRef = claim('workflow_ref');
  final shape = _oidcShapeFor(claims['environment']);
  final rawJobWorkflowRef = claims['job_workflow_ref'];
  if (rawJobWorkflowRef != null &&
      (rawJobWorkflowRef is! String || rawJobWorkflowRef.isEmpty)) {
    throw _invalidOidc;
  }
  final jobWorkflowRef = rawJobWorkflowRef as String? ?? '';
  final actor = claim('actor');
  final subject = claim('sub');
  final environment = claim('environment');
  final issuedAt = claims['iat'];
  final expiresAt = claims['exp'];
  final trustedRef = _trustedRef(shape, sha);
  if (!_repository.hasMatch(repository) ||
      !_sha.hasMatch(sha) ||
      ref != trustedRef ||
      claims['event_name'] != 'workflow_dispatch' ||
      workflowRef !=
          '$repository/.github/workflows/${shape.workflow}@$trustedRef' ||
      subject != 'repo:$repository:environment:${shape.environment}' ||
      environment != shape.environment ||
      !_jobWorkflowRefAllowed(
        jobWorkflowRef,
        shape,
        repository,
        trustedRef,
        agentRepositories,
      ) ||
      issuedAt is! num ||
      expiresAt is! num) {
    throw _invalidOidc;
  }
  final issued = DateTime.fromMillisecondsSinceEpoch(
    issuedAt.toInt() * 1000,
    isUtc: true,
  );
  final current = now.toUtc();
  final expires = DateTime.fromMillisecondsSinceEpoch(
    expiresAt.toInt() * 1000,
    isUtc: true,
  );
  if (issued.isAfter(current.add(const Duration(seconds: 30))) ||
      current.difference(issued) > const Duration(minutes: 10) ||
      !expires.isAfter(current.subtract(const Duration(seconds: 30))) ||
      expires.difference(issued) > const Duration(minutes: 15)) {
    throw _invalidOidc;
  }
  return GitHubActionsPrincipal(
    repository: repository,
    repositoryId: repositoryId,
    runId: runId,
    runAttempt: runAttempt,
    sha: sha,
    ref: ref,
    workflowRef: workflowRef,
    jobWorkflowRef: jobWorkflowRef,
    actor: actor,
    subject: subject,
    environment: environment,
  );
}

/// The exact identity one ii-os workflow is allowed to present.
///
/// Every field is pinned together: a token is only accepted when its
/// environment, immutable tag, and workflow file all belong to the same shape,
/// so the permission installer can never present itself as an agent task.
final class _OidcShape {
  const _OidcShape({
    required this.environment,
    required this.tagPrefix,
    required this.workflow,
    this.implWorkflow,
  });

  final String environment;
  final String tagPrefix;
  final String workflow;

  /// Reviewed body this shape must run through, when the dispatched workflow
  /// is a thin caller rather than the implementation itself.
  final String? implWorkflow;
}

/// Whether `job_workflow_ref` names a body this shape is allowed to run.
///
/// A shape that pins a reusable implementation may only ever run through the
/// coordinator repository at an exact commit, so an absent claim or a body in
/// the dispatching repository is rejected. Every other shape runs the
/// dispatched workflow itself, at the same immutable tag.
bool _jobWorkflowRefAllowed(
  String jobWorkflowRef,
  _OidcShape shape,
  String repository,
  String trustedRef,
  AgentRepositoryTopology agentRepositories,
) {
  final impl = shape.implWorkflow;
  if (impl == null) {
    return jobWorkflowRef.isEmpty ||
        (jobWorkflowRef.startsWith('$repository/.github/workflows/') &&
            jobWorkflowRef.endsWith('@$trustedRef'));
  }
  const separator = '@';
  final coordinator = agentRepositories.coordinatorRepository;
  if (coordinator.isEmpty) return false;
  final prefix = '$coordinator/.github/workflows/$impl$separator';
  if (!jobWorkflowRef.startsWith(prefix)) return false;
  return _sha.hasMatch(jobWorkflowRef.substring(prefix.length));
}

const _agentTaskShape = _OidcShape(
  environment: iiOsAgentEnvironment,
  tagPrefix: 'ii-os-agent-v4-',
  workflow: iiOsAgentTaskWorkflow,
);

const _permissionInstallerShape = _OidcShape(
  environment: iiOsAgentBootstrapEnvironment,
  tagPrefix: 'ii-os-agent-v4-bootstrap-',
  workflow: iiOsAgentPermissionInstallerWorkflow,
  implWorkflow: iiOsAgentPermissionInstallerImplWorkflow,
);

/// The ref a token of this shape must carry: an immutable tag of the commit.
String _trustedRef(_OidcShape shape, String sha) {
  return 'refs/tags/${shape.tagPrefix}$sha';
}

_OidcShape _oidcShapeFor(Object? environment) {
  return environment == iiOsAgentBootstrapEnvironment
      ? _permissionInstallerShape
      : _agentTaskShape;
}

final _repository = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');
final _sha = RegExp(r'^[0-9a-f]{40}$');
final _safeKid = RegExp(r'^[A-Za-z0-9._-]{1,200}$');
final _invalidOidc = ApiError(
  401,
  'github_actions_oidc_invalid',
  'GitHub Actions identity could not be verified.',
);

DateTime _utcNow() => DateTime.now().toUtc();
