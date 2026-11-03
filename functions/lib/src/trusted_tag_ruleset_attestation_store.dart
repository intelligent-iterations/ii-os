import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'auth_service.dart';
import 'workspace_store.dart';

bool trustedTagRulesetSnapshotMatches({
  required Map<String, Object?> ruleset,
  required int expectedRulesetId,
  required String expectedRulesetUpdatedAt,
}) =>
    ruleset['id'] == expectedRulesetId &&
    ruleset['updated_at'] == expectedRulesetUpdatedAt;

/// One human verification of the GitHub field a read-only App cannot see.
///
/// GitHub omits `bypass_actors` unless the caller can write the ruleset. ii-os
/// deliberately does not hold that authority, so a workspace administrator
/// verifies the empty bypass list in GitHub. The attestation is bound to the
/// exact ruleset identity and GitHub `updated_at` value; any ruleset edit makes
/// it stale and blocks agent work until it is reviewed again.
final class TrustedTagRulesetAttestation {
  const TrustedTagRulesetAttestation({
    required this.repository,
    required this.installationId,
    required this.rulesetId,
    required this.rulesetUpdatedAt,
    required this.rulesetSource,
    required this.rulesetSourceType,
    required this.attestedBy,
    required this.attestedAt,
  });

  factory TrustedTagRulesetAttestation.fromData(Map<String, Object?> data) {
    final installationId = data['installationId'];
    final rulesetId = data['rulesetId'];
    final attestedAt = data['attestedAt'];
    return TrustedTagRulesetAttestation(
      repository: data['repository'] is String
          ? data['repository']! as String
          : '',
      installationId: installationId is num ? installationId.toInt() : 0,
      rulesetId: rulesetId is num ? rulesetId.toInt() : 0,
      rulesetUpdatedAt: data['rulesetUpdatedAt'] is String
          ? data['rulesetUpdatedAt']! as String
          : '',
      rulesetSource: data['rulesetSource'] is String
          ? data['rulesetSource']! as String
          : '',
      rulesetSourceType: data['rulesetSourceType'] is String
          ? data['rulesetSourceType']! as String
          : '',
      attestedBy: data['attestedBy'] is String
          ? data['attestedBy']! as String
          : '',
      attestedAt: attestedAt is Timestamp
          ? attestedAt.toDate().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String repository;
  final int installationId;
  final int rulesetId;
  final String rulesetUpdatedAt;
  final String rulesetSource;
  final String rulesetSourceType;
  final String attestedBy;
  final DateTime attestedAt;

  bool matches({
    required String currentRepository,
    required int currentInstallationId,
    required Map<String, Object?> ruleset,
  }) {
    final currentRulesetId = ruleset['id'];
    return repository == currentRepository &&
        installationId == currentInstallationId &&
        currentRulesetId is num &&
        rulesetId == currentRulesetId.toInt() &&
        rulesetUpdatedAt == ruleset['updated_at'] &&
        rulesetSource == ruleset['source'] &&
        rulesetSourceType == ruleset['source_type'];
  }
}

final class TrustedTagRulesetAttestationStore {
  TrustedTagRulesetAttestationStore(this.store);

  final WorkspaceStore store;

  Future<TrustedTagRulesetAttestation?> read({
    required String workspaceId,
    required String repository,
  }) async {
    final data = (await _ref(workspaceId, repository).get()).data();
    if (data == null) return null;
    final attestation = TrustedTagRulesetAttestation.fromData(data);
    return attestation.repository == repository &&
            attestation.installationId > 0 &&
            attestation.rulesetId > 0 &&
            attestation.rulesetUpdatedAt.isNotEmpty &&
            attestation.rulesetSource.isNotEmpty &&
            attestation.rulesetSourceType.isNotEmpty &&
            attestation.attestedBy.isNotEmpty
        ? attestation
        : null;
  }

  Future<TrustedTagRulesetAttestation> attest({
    required String workspaceId,
    required String repository,
    required int installationId,
    required Map<String, Object?> ruleset,
    required AuthenticatedUser actor,
  }) async {
    final rulesetId = ruleset['id'];
    final rulesetUpdatedAt = ruleset['updated_at'];
    final rulesetSource = ruleset['source'];
    final rulesetSourceType = ruleset['source_type'];
    if (installationId <= 0 ||
        rulesetId is! num ||
        rulesetId.toInt() <= 0 ||
        rulesetUpdatedAt is! String ||
        DateTime.tryParse(rulesetUpdatedAt) == null ||
        rulesetSource is! String ||
        rulesetSource.isEmpty ||
        rulesetSourceType is! String ||
        rulesetSourceType.isEmpty) {
      throw StateError('Cannot attest an incomplete GitHub ruleset snapshot.');
    }
    final now = Timestamp.now();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      'repository': repository,
      'installationId': installationId,
      'rulesetId': rulesetId.toInt(),
      'rulesetUpdatedAt': rulesetUpdatedAt,
      'rulesetSource': rulesetSource,
      'rulesetSourceType': rulesetSourceType,
      'attestedBy': actor.uid,
      'attestedAt': now,
    };
    await _ref(workspaceId, repository).set(data);
    return TrustedTagRulesetAttestation.fromData(data);
  }

  DocumentReference<Map<String, Object?>> _ref(
    String workspaceId,
    String repository,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('trustedTagRulesetAttestations')
      .doc(sha256.convert(utf8.encode(repository)).toString());
}
