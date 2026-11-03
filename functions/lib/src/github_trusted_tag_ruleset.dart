part of 'github_client.dart';

extension GitHubTrustedTagRuleset on GitHubClient {
  Future<Map<String, Object?>> _trustedTagProtectionCheck(
    Workspace workspace, {
    required String repository,
    TrustedTagRulesetAttestation? attestation,
  }) async {
    try {
      final rulesets = await _trustedTagRulesets(
        workspace,
        repository: repository,
      );
      final protected = githubTrustedTagRulesetProtected(rulesets);
      final hiddenRulesets = rulesets
          .where((ruleset) => githubTrustedTagRulesetBypassHidden([ruleset]))
          .toList();
      if (!protected && hiddenRulesets.length > 1) {
        return readinessCheck(
          id: 'immutable_tag_protection',
          label: 'Trusted agent tags cannot be changed',
          passed: false,
          repository: repository,
          detail:
              'GitHub has ${hiddenRulesets.length} active rulesets protecting ii-os-agent-v4-* tags, but it hides their bypass lists from the read-only App.',
          guidance:
              'Consolidate this protection into exactly one active ruleset, then review its empty bypass list.',
        );
      }
      final hiddenRuleset = hiddenRulesets.firstOrNull;
      if (!protected && hiddenRuleset != null) {
        final installationId = workspace.githubInstallationId;
        final attested =
            installationId != null &&
            attestation?.matches(
                  currentRepository: repository,
                  currentInstallationId: installationId,
                  ruleset: hiddenRuleset,
                ) ==
                true;
        final rulesetId = hiddenRuleset['id'];
        final updatedAt = hiddenRuleset['updated_at'];
        return {
          ...readinessCheck(
            id: 'immutable_tag_protection',
            label: 'Trusted agent tags cannot be changed',
            passed: attested,
            repository: repository,
            detail: attested
                ? 'Ruleset #$rulesetId is active, unchanged since $updatedAt, and has a current workspace-admin attestation that no actor can bypass it.'
                : 'Ruleset #$rulesetId is active and the connected App cannot bypass it. GitHub hides every other bypass actor from an App that cannot change repository rules.',
            guidance: attested
                ? ''
                : 'Open this exact ruleset and verify that its final \u201cRestrictions\u201d section says \u201cNo restrictions have been added\u201d (an empty bypass list), then record that review in ii-os. The approval is invalidated automatically when GitHub changes the ruleset.',
          ),
          'rulesetId': rulesetId,
          'rulesetUpdatedAt': updatedAt,
          'requiresNoBypassAttestation': !attested,
        };
      }
      return readinessCheck(
        id: 'immutable_tag_protection',
        label: 'Trusted agent tags cannot be changed',
        passed: protected,
        repository: repository,
        detail: protected
            ? 'An active no-bypass ruleset blocks updates and deletion of ii-os-agent-v4-* tags.'
            : 'No active no-bypass ruleset blocks both updates and deletion of ii-os-agent-v4-* tags.',
        guidance: protected
            ? ''
            : 'Add an active tag ruleset for ii-os-agent-v4-* that blocks updates and deletion and has no bypass actors.',
      );
    } on ApiError catch (error) {
      return readinessFromGitHubError(
        id: 'immutable_tag_protection',
        label: 'Trusted agent tags cannot be changed',
        repository: repository,
        error: error,
        missingCodes: const {'github_resource_not_found'},
        guidance:
            'Grant Administration read access and configure the no-bypass trusted-tag ruleset.',
      );
    }
  }

  /// Returns the exact live ruleset snapshot a human is allowed to attest.
  ///
  /// The App proves every visible field and that it cannot bypass the rules.
  /// A human confirms only GitHub's deliberately hidden bypass-actor list.
  Future<Map<String, Object?>> trustedTagRulesetForAttestation(
    Workspace workspace, {
    required String repository,
  }) async {
    final rulesets = await _trustedTagRulesets(
      workspace,
      repository: repository,
    );
    final candidates = rulesets
        .where((ruleset) => githubTrustedTagRulesetBypassHidden([ruleset]))
        .toList();
    if (candidates.length != 1) {
      throw const ApiError(
        409,
        'trusted_tag_ruleset_not_attestable',
        'Exactly one active trusted-tag ruleset must match before its hidden bypass list can be reviewed.',
      );
    }
    final ruleset = candidates.single;
    final id = ruleset['id'];
    final updatedAt = ruleset['updated_at'];
    final source = ruleset['source'];
    final sourceType = ruleset['source_type'];
    if (id is! num ||
        id.toInt() <= 0 ||
        updatedAt is! String ||
        DateTime.tryParse(updatedAt) == null ||
        source is! String ||
        source.isEmpty ||
        sourceType is! String ||
        sourceType.isEmpty) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an incomplete trusted-tag ruleset snapshot.',
      );
    }
    return ruleset;
  }

  Future<List<Map<String, Object?>>> _trustedTagRulesets(
    Workspace workspace, {
    required String repository,
  }) async {
    final response = await _rest(
      workspace,
      'GET',
      '/repos/$repository/rulesets?targets=tag&includes_parents=true&per_page=100',
    );
    if (response is! List<Object?> ||
        response.length > 100 ||
        response.length != response.whereType<Map<String, Object?>>().length) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid repository rulesets.',
      );
    }
    final rulesets = <Map<String, Object?>>[];
    for (final summary in response.whereType<Map<String, Object?>>()) {
      final id = summary['id'];
      if (id is! num || id.toInt() <= 0) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub returned an invalid repository ruleset identity.',
        );
      }
      rulesets.add(
        _asMap(
          await _rest(
            workspace,
            'GET',
            '/repos/$repository/rulesets/${id.toInt()}',
          ),
        ),
      );
    }
    return rulesets;
  }
}
