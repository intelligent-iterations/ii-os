part of 'github_client.dart';

const String _agentPermissionDirectory = '.ii-os/agent-permissions';

AgentPermissionProfile agentPermissionProfileFromListing(
  Map<String, Object?> listing,
) {
  final source = Map<String, Object?>.of(listing)
    ..remove('repository')
    ..remove('ref')
    ..remove('path')
    ..remove('sha');
  return AgentPermissionProfile.parse(source);
}

AgentPermissionProfile? executableAgentPermissionProfileFromListings(
  Iterable<Map<String, Object?>> listings,
  String id,
) {
  for (final listing in listings) {
    if (listing['id'] != id) continue;
    final profile = agentPermissionProfileFromListing(listing);
    requireExecutableAgentProfile(profile);
    return profile;
  }
  return null;
}

extension GitHubAgentPermissions on GitHubClient {
  Future<List<Map<String, Object?>>> listAgentPermissionProfiles(
    Workspace workspace, {
    required String repository,
    required String ref,
  }) async {
    _requireRepository(workspace, repository);
    requireAgentPermissionReadRef(ref);
    final encodedRef = Uri.encodeQueryComponent(ref);
    final response = await _rest(
      workspace,
      'GET',
      '/repos/$repository/contents/$_agentPermissionDirectory?ref=$encodedRef',
    );
    if (response is! List<Object?>) {
      throw const ApiError(
        502,
        'agent_permissions_response_invalid',
        'GitHub returned invalid agent permission data.',
      );
    }
    final profiles = <Map<String, Object?>>[];
    for (final entry in response.whereType<Map<String, Object?>>()) {
      final name = entry['name'];
      if (name is! String || !_agentPermissionFile.hasMatch(name)) continue;
      final file = _asMap(
        await _rest(
          workspace,
          'GET',
          '/repos/$repository/contents/$_agentPermissionDirectory/$name?ref=$encodedRef',
        ),
      );
      final content = file['content'];
      if (content is! String || file['encoding'] != 'base64') {
        throw const ApiError(
          502,
          'agent_permissions_response_invalid',
          'GitHub returned an unreadable agent permission file.',
        );
      }
      final source = utf8.decode(base64Decode(content.replaceAll('\n', '')));
      final profile = AgentPermissionProfile.parse(source);
      profiles.add({
        ...profile.toJson(),
        'repository': repository,
        'ref': ref,
        'path': '$_agentPermissionDirectory/$name',
        'sha': file['sha'],
      });
    }
    profiles.sort(
      (left, right) => (left['display_name'] as String).compareTo(
        right['display_name'] as String,
      ),
    );
    return profiles;
  }

  /// The immutable tag the permission installer must run on.
  ///
  /// The installer asserts its own ref equals this tag, so a dispatch on any
  /// other ref dies inside the run with nothing to show the operator. Resolve
  /// it first and fail with something actionable instead.
  ///
  /// ii-os deliberately does not mint this tag: it is what proves the installed
  /// source was reviewed. A repository owner or their own automation creates
  /// it outside the system being approved.
  Future<String> resolveBootstrapTag(
    Workspace workspace, {
    required String repository,
  }) async {
    _requireRepository(workspace, repository);
    final branch = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository/branches/dev'),
    );
    final commit = branch['commit'];
    final sha = commit is Map<String, Object?> ? commit['sha'] : null;
    if (sha is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid dev commit identity.',
      );
    }
    final tag = 'ii-os-agent-v4-bootstrap-$sha';
    final matching = await _rest(
      workspace,
      'GET',
      '/repos/$repository/git/matching-refs/tags/$tag',
    );
    final found =
        matching is List<Object?> &&
        matching.whereType<Map<String, Object?>>().any((item) {
          final object = item['object'];
          return item['ref'] == 'refs/tags/$tag' &&
              object is Map<String, Object?> &&
              object['type'] == 'commit' &&
              object['sha'] == sha;
        });
    if (!found) {
      throw ApiError(
        409,
        'permission_bootstrap_tag_missing',
        'This repository still needs a one-time release marker before agent '
            'permissions can be installed. Ask someone with write access to '
            '$repository to create the tag shown below on the current dev '
            'commit, then try again.',
        details: {
          'repository': repository,
          'tag': tag,
          'sha': sha,
          'command': 'git tag $tag $sha && git push origin $tag',
          'why':
              'The marker is what proves the installer code was reviewed, so '
              'ii-os deliberately cannot create it for you.',
        },
      );
    }
    return tag;
  }

  Future<Map<String, Object?>> dispatchAgentPermissionInstaller(
    Workspace workspace, {
    required String repository,
    required String ref,
    required Map<String, String> inputs,
  }) async {
    _requireRepository(workspace, repository);
    requireAgentPermissionDispatchRef(ref);
    final key = '$repository#$iiOsAgentPermissionInstallerWorkflow';
    if (!workspace.workflows.contains(key)) {
      throw const ApiError(
        400,
        'workflow_not_allowed',
        'The permission installer is not enabled for this workspace.',
      );
    }
    if (inputs.length > 20 ||
        inputs.entries.any(
          (entry) =>
              !_agentPermissionInputName.hasMatch(entry.key) ||
              entry.value.length > 50000,
        )) {
      throw const ApiError(
        400,
        'workflow_input_invalid',
        'A permission installer input is invalid or too large.',
      );
    }
    await dispatchWorkflow(
      workspace,
      repository: repository,
      workflowPath: '.github/workflows/$iiOsAgentPermissionInstallerWorkflow',
      ref: ref,
      inputs: inputs,
    );
    return {
      'accepted': true,
      'repository': repository,
      'workflow': iiOsAgentPermissionInstallerWorkflow,
      'ref': ref,
    };
  }
}

final RegExp _agentPermissionFile = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json$',
);
final RegExp _agentPermissionInputName = RegExp(
  r'^[A-Za-z][A-Za-z0-9_-]{0,63}$',
);
void requireAgentPermissionRef(String ref) {
  if (ref != 'dev') {
    throw const ApiError(
      400,
      'permission_ref_invalid',
      'Agent permission profiles can only be read from or installed on dev.',
    );
  }
}

/// The installer may only be dispatched on an immutable bootstrap tag.
void requireAgentPermissionDispatchRef(String ref) {
  if (!RegExp(r'^ii-os-agent-v4-bootstrap-[0-9a-f]{40}$').hasMatch(ref)) {
    throw const ApiError(
      400,
      'permission_ref_invalid',
      'The permission installer can only run on an immutable bootstrap tag.',
    );
  }
}

void requireAgentPermissionReadRef(String ref) {
  if (ref != 'dev' && !RegExp(r'^[0-9a-f]{40}$').hasMatch(ref)) {
    throw const ApiError(
      400,
      'permission_ref_invalid',
      'Agent permission profiles can only be read from dev or an immutable commit.',
    );
  }
}
