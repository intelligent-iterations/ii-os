import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'domain.dart';
import 'interactive_session.dart';
import 'interactive_session_workspace_access.dart';
import 'organization_resources.dart';
import 'providers/fleet/interactive_session_execution.dart';
import 'session_relay_control.dart';
import 'workspace_resource_grants.dart';

final class InteractiveSessionCoordinator {
  InteractiveSessionCoordinator({
    required this.workspaces,
    required this.sessions,
    required this.relay,
    required this.signer,
    required this.image,
    DateTime Function()? clock,
    Uuid? uuid,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _uuid = uuid ?? const Uuid();

  final InteractiveSessionWorkspaceAccess workspaces;
  final InteractiveSessionRepository sessions;
  final SessionRelayControl relay;
  final SessionGrantSigner signer;
  final String image;
  final DateTime Function() _clock;
  final Uuid _uuid;

  Future<Map<String, Object?>> create({
    required AuthenticatedUser actor,
    required String workspaceId,
    String runnerResourceId = '',
  }) async {
    final access = await workspaces.require(
      actor,
      workspaceId,
      Capability.interactiveSessionsLaunch,
    );
    final placement = _placement(access.workspace, runnerResourceId);
    final now = _clock();
    final sessionId = _uuid.v4();
    final relayUri = relay.connectUri(sessionId);
    final descriptor = InteractiveSessionDescriptor(
      id: sessionId,
      organizationId: access.workspace.organizationId,
      workspaceId: workspaceId,
      ownerSubject: actor.uid,
      runnerResourceId: placement.grant.resourceId,
      poolId: placement.pool.providerPoolId,
      jobId: 'ii-os:interactive:$workspaceId:$sessionId',
      image: image,
      lifecycle: SessionLifecycle.requested,
      policyRevision: 1,
      createdAt: now,
      expiresAt: now.add(interactiveSessionLifetime),
    );
    final record = InteractiveSessionRecord(
      descriptor: descriptor,
      relayUri: relayUri,
      participants: [
        InteractiveSessionParticipant(
          subject: actor.uid,
          role: ParticipantRole.owner,
          generation: 1,
        ),
      ],
    );
    final fleetRequest = buildInteractiveCoderRequest(
      organizationId: access.workspace.organizationId,
      workspaceId: workspaceId,
      actorUid: actor.uid,
      sessionId: sessionId,
      runnerResourceId: placement.grant.resourceId,
      poolId: placement.pool.providerPoolId,
      relayUrl: relayUri.toString(),
      image: image,
      submittedAt: now,
    );
    await relay.register(descriptor);
    try {
      await sessions.create(
        session: record,
        fleetRequest: fleetRequest,
        maxConcurrent: placement.grant.maxConcurrent,
      );
    } on Object {
      try {
        await relay.discard(sessionId);
      } on Object {
        // The relay entry is bounded by the descriptor expiry. Preserve the
        // original storage error and never submit the Fleet job.
      }
      rethrow;
    }
    await relay.ready(sessionId);
    return {
      'session': record.toJson(),
      'attach': _attachment(record, record.participants.single),
    };
  }

  Future<Map<String, Object?>> listPage({
    required AuthenticatedUser actor,
    required String workspaceId,
  }) async {
    final access = await workspaces.require(
      actor,
      workspaceId,
      Capability.interactiveSessionsRead,
    );
    final records = await sessions.list(workspaceId);
    return {
      'sessions': records.map((item) => item.toJson()).toList(),
      'runnerPools': _launchPools(access.workspace),
      'stale': false,
      'limit': interactiveSessionListLimit,
    };
  }

  Future<Map<String, Object?>> get({
    required AuthenticatedUser actor,
    required String workspaceId,
    required String sessionId,
  }) async {
    await workspaces.require(
      actor,
      workspaceId,
      Capability.interactiveSessionsRead,
    );
    return (await sessions.get(workspaceId, sessionId)).toJson();
  }

  Future<Map<String, Object?>> attach({
    required AuthenticatedUser actor,
    required String workspaceId,
    required String sessionId,
  }) async {
    await workspaces.require(
      actor,
      workspaceId,
      Capability.interactiveSessionsRead,
    );
    final session = await sessions.get(workspaceId, sessionId);
    _requireJoinable(session, _clock());
    final participant = session.participant(actor.uid);
    if (participant == null || participant.revoked) {
      throw const ApiError(
        403,
        'interactive_session_invite_required',
        'You have not been invited to this interactive session.',
      );
    }
    return _attachment(session, participant);
  }

  Future<Map<String, Object?>> putParticipant({
    required AuthenticatedUser actor,
    required String workspaceId,
    required String sessionId,
    required String subject,
    required ParticipantRole role,
  }) async {
    if (!const {
          ParticipantRole.collaborator,
          ParticipantRole.viewer,
          ParticipantRole.agent,
        }.contains(role) ||
        subject.isEmpty ||
        subject.length > 200) {
      throw const ApiError(
        400,
        'interactive_participant_invalid',
        'Choose a collaborator, viewer, or session agent.',
      );
    }
    final current = await _requireManager(actor, workspaceId, sessionId);
    if (role != ParticipantRole.agent) {
      final membership = await workspaces.membership(workspaceId, subject);
      if (membership == null || membership.suspended) {
        throw const ApiError(
          409,
          'interactive_participant_not_member',
          'Human participants must be active workspace members.',
        );
      }
    } else if (!subject.startsWith('agent:')) {
      throw const ApiError(
        400,
        'interactive_agent_subject_invalid',
        'Session agent identities must begin with agent: .',
      );
    }
    final nextGeneration = (current.participant(subject)?.generation ?? 0) + 1;
    await relay.rotateParticipant(sessionId, subject, nextGeneration);
    final updated = await sessions.putParticipant(
      workspaceId: workspaceId,
      sessionId: sessionId,
      participant: InteractiveSessionParticipant(
        subject: subject,
        role: role,
        generation: 1,
      ),
    );
    await relay.rotateParticipant(
      sessionId,
      subject,
      updated.participant(subject)!.generation,
    );
    await relay.update(updated.descriptor);
    return updated.toJson();
  }

  Future<Map<String, Object?>> revokeParticipant({
    required AuthenticatedUser actor,
    required String workspaceId,
    required String sessionId,
    required String subject,
  }) async {
    final current = await _requireManager(actor, workspaceId, sessionId);
    if (subject == current.descriptor.ownerSubject) {
      throw const ApiError(
        409,
        'interactive_owner_immutable',
        'The session owner cannot be revoked.',
      );
    }
    final existing = current.participant(subject);
    if (existing == null) {
      throw const ApiError(
        404,
        'interactive_session_participant_not_found',
        'Interactive session participant not found.',
      );
    }
    await relay.rotateParticipant(sessionId, subject, existing.generation + 1);
    final updated = await sessions.revokeParticipant(
      workspaceId: workspaceId,
      sessionId: sessionId,
      subject: subject,
    );
    await relay.rotateParticipant(
      sessionId,
      subject,
      updated.participant(subject)!.generation,
    );
    await relay.update(updated.descriptor);
    return updated.toJson();
  }

  Future<Map<String, Object?>> issueUiAccess({
    required AuthenticatedUser actor,
    required String workspaceId,
    required String sessionId,
    required String agentSubject,
    required bool allowAct,
  }) async {
    final session = await _requireManager(actor, workspaceId, sessionId);
    _requireJoinable(session, _clock());
    final agent = session.participant(agentSubject);
    if (agent == null || agent.revoked || agent.role != ParticipantRole.agent) {
      throw const ApiError(
        409,
        'interactive_agent_not_granted',
        'Add this session agent before granting frontend access.',
      );
    }
    final frontend = InteractiveSessionParticipant(
      subject: 'frontend:${actor.uid}:${_uuid.v4()}',
      role: ParticipantRole.frontend,
      generation: 1,
    );
    final now = _clock();
    final expiresAt = _grantExpiry(session, now);
    return {
      'relayUri': session.relayUri.toString(),
      'frontendGrant': _grant(
        session,
        frontend,
        const {SessionCapability.sessionJoin, SessionCapability.frontend},
        now,
        expiresAt,
      ),
      'agentGrant': _grant(
        session,
        agent,
        {
          SessionCapability.sessionJoin,
          SessionCapability.uiObserve,
          if (allowAct) SessionCapability.uiAct,
        },
        now,
        expiresAt,
      ),
      'expiresAt': expiresAt.toIso8601String(),
      'allowAct': allowAct,
    };
  }

  Future<Map<String, Object?>> stop({
    required AuthenticatedUser actor,
    required String workspaceId,
    required String sessionId,
  }) async {
    await _requireManager(actor, workspaceId, sessionId);
    final updated = await sessions.stop(
      workspaceId: workspaceId,
      sessionId: sessionId,
      now: _clock(),
    );
    await relay.end(sessionId);
    return updated.toJson();
  }

  Future<InteractiveSessionRecord> _requireManager(
    AuthenticatedUser actor,
    String workspaceId,
    String sessionId,
  ) async {
    final access = await workspaces.require(
      actor,
      workspaceId,
      Capability.interactiveSessionsRead,
    );
    final session = await sessions.get(workspaceId, sessionId);
    if (session.descriptor.ownerSubject != actor.uid &&
        !access.membership.allows(Capability.interactiveSessionsManage)) {
      throw const ApiError(
        403,
        'interactive_session_manage_denied',
        'Only the session owner or a workspace session manager may do that.',
      );
    }
    return session;
  }

  Map<String, Object?> _attachment(
    InteractiveSessionRecord session,
    InteractiveSessionParticipant participant,
  ) {
    final now = _clock();
    final expiresAt = _grantExpiry(session, now);
    return {
      'relayUri': session.relayUri.toString(),
      'grant': _grant(
        session,
        participant,
        _roleCapabilities(participant.role),
        now,
        expiresAt,
      ),
      'subject': participant.subject,
      'role': participant.role.name,
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  String _grant(
    InteractiveSessionRecord session,
    InteractiveSessionParticipant participant,
    Set<SessionCapability> capabilities,
    DateTime now,
    DateTime expiresAt,
  ) {
    return signer.mint(
      SessionGrantClaims(
        audience: 'ii-session-relay',
        sessionId: session.descriptor.id,
        organizationId: session.descriptor.organizationId,
        workspaceId: session.descriptor.workspaceId,
        subject: participant.subject,
        role: participant.role,
        capabilities: capabilities,
        generation: participant.generation,
        policyRevision: session.descriptor.policyRevision,
        tokenId: signer.newTokenId(),
        issuedAt: now,
        expiresAt: expiresAt,
        jobId: session.descriptor.jobId,
        leaseId: session.descriptor.leaseId,
      ),
    );
  }
}

DateTime _grantExpiry(InteractiveSessionRecord session, DateTime now) {
  final candidate = now.add(interactiveAttachGrantLifetime);
  return session.descriptor.expiresAt.isBefore(candidate)
      ? session.descriptor.expiresAt
      : candidate;
}

({WorkspaceRunnerGrant grant, OrganizationRunnerPool pool}) _placement(
  Workspace workspace,
  String requestedResourceId,
) {
  if (workspace.organizationId.isEmpty || !workspace.resourceGrantsExplicit) {
    throw const ApiError(
      409,
      'interactive_runner_grant_required',
      'Select an exact organization Fleet pool for this workspace first.',
    );
  }
  final errors = workspace.resourceGrants.validateAgainst(
    workspace.organizationResources,
  );
  if (errors.isNotEmpty) {
    throw ApiError(
      409,
      'interactive_runner_grant_stale',
      'The workspace runner grant is no longer valid.',
      details: {'errors': errors.toList()..sort()},
    );
  }
  final grant = requestedResourceId.isEmpty
      ? workspace.resourceGrants.runners
            .where((item) => item.primary)
            .firstOrNull
      : workspace.resourceGrants.runners
            .where((item) => item.resourceId == requestedResourceId)
            .firstOrNull;
  final pool = grant == null
      ? null
      : workspace.organizationResources.runner(grant.resourceId);
  const required = {'runtime-docker', 'interactive-pty'};
  if (grant == null ||
      pool == null ||
      !pool.active ||
      pool.provider != 'fleet' ||
      pool.providerPoolId.isEmpty ||
      !grant.capabilities.containsAll(required) ||
      grant.maxCpu < 2 ||
      grant.maxRamMiB < 2048) {
    throw const ApiError(
      409,
      'interactive_runner_pool_unavailable',
      'The selected Fleet pool cannot run the interactive terminal profile.',
    );
  }
  return (grant: grant, pool: pool);
}

void _requireJoinable(InteractiveSessionRecord session, DateTime now) {
  if (!session.descriptor.expiresAt.isAfter(now) ||
      const {
        SessionLifecycle.ending,
        SessionLifecycle.cleaning,
        SessionLifecycle.cleaned,
        SessionLifecycle.failed,
      }.contains(session.descriptor.lifecycle)) {
    throw const ApiError(
      409,
      'interactive_session_not_joinable',
      'This interactive session cannot accept new connections.',
    );
  }
}

List<Map<String, Object?>> _launchPools(Workspace workspace) {
  if (!workspace.resourceGrantsExplicit ||
      workspace.resourceGrants
          .validateAgainst(workspace.organizationResources)
          .isNotEmpty) {
    return const [];
  }
  const required = {'runtime-docker', 'interactive-pty'};
  final result = <Map<String, Object?>>[];
  for (final grant in workspace.resourceGrants.runners) {
    final pool = workspace.organizationResources.runner(grant.resourceId);
    if (pool == null ||
        !pool.active ||
        pool.provider != 'fleet' ||
        pool.providerPoolId.isEmpty ||
        !grant.capabilities.containsAll(required) ||
        grant.maxCpu < 2 ||
        grant.maxRamMiB < 2048 ||
        grant.maxConcurrent < 1 ||
        grant.maxConcurrent > 20) {
      continue;
    }
    result.add({
      'resourceId': grant.resourceId,
      'name': pool.name,
      'providerPoolId': pool.providerPoolId,
      'primary': grant.primary,
      'capabilities': grant.capabilities.toList()..sort(),
      'maxCpu': grant.maxCpu,
      'maxRamMiB': grant.maxRamMiB,
      'maxConcurrent': grant.maxConcurrent,
    });
  }
  return result;
}

Set<SessionCapability> _roleCapabilities(ParticipantRole role) =>
    switch (role) {
      ParticipantRole.owner => const {
        SessionCapability.sessionJoin,
        SessionCapability.sessionManage,
        SessionCapability.terminalObserve,
        SessionCapability.terminalWrite,
        SessionCapability.terminalSignal,
        SessionCapability.uiObserve,
        SessionCapability.uiAct,
      },
      ParticipantRole.collaborator => const {
        SessionCapability.sessionJoin,
        SessionCapability.terminalObserve,
        SessionCapability.terminalWrite,
        SessionCapability.uiObserve,
      },
      ParticipantRole.viewer => const {
        SessionCapability.sessionJoin,
        SessionCapability.terminalObserve,
        SessionCapability.uiObserve,
      },
      ParticipantRole.agent => const {
        SessionCapability.sessionJoin,
        SessionCapability.terminalObserve,
      },
      ParticipantRole.supervisor => const {
        SessionCapability.sessionJoin,
        SessionCapability.supervisor,
      },
      ParticipantRole.frontend => const {
        SessionCapability.sessionJoin,
        SessionCapability.frontend,
      },
    };
