import 'dart:async';
import 'dart:convert';

import 'frame.dart';
import 'grant.dart';
import 'protocol.dart';
import 'relay.dart';

part 'fake_relay_state.dart';
part 'fake_relay_ui.dart';

/// Deterministic, bounded relay used by package consumers and conformance tests.
/// It deliberately implements the same authorization decisions as a remote
/// relay without opening a socket or persisting terminal bytes.
class InMemorySessionRelay implements SessionTransport {
  InMemorySessionRelay({
    required this.signer,
    this.supervisorSigner,
    this.limits = const InteractiveSessionLimits(),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    limits.validate();
  }

  final SessionGrantSigner signer;
  final SessionGrantSigner? supervisorSigner;
  final InteractiveSessionLimits limits;
  final DateTime Function() _clock;
  final Map<String, _RelaySession> _sessions = {};
  final Map<String, DateTime> _consumedTokenIds = {};

  int get sessionCount => _sessions.length;

  bool hasSession(String sessionId) => _sessions.containsKey(sessionId);

  void register(InteractiveSessionDescriptor descriptor) {
    if (_sessions.containsKey(descriptor.id)) {
      throw const SessionProtocolException('session_already_exists');
    }
    _validateSessionDescriptor(descriptor, limits, _clock());
    final session = _RelaySession(descriptor, limits);
    _sessions[descriptor.id] = session;
    session.expiryTimer = Timer(
      descriptor.expiresAt.difference(_clock()),
      () => _expire(descriptor.id),
    );
  }

  void discard(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const SessionProtocolException('session_missing');
    }
    if (session.connections.isNotEmpty) {
      throw const SessionProtocolException('session_has_connections');
    }
    session.expiryTimer?.cancel();
    session.retentionTimer?.cancel();
    _sessions.remove(sessionId);
  }

  /// Replaces control-plane metadata without disturbing live connections or
  /// bounded replay state. Runtime identity fields may be filled after Fleet
  /// placement and policy revisions may advance, but immutable scope cannot.
  void update(InteractiveSessionDescriptor descriptor) {
    final session = _requireSession(descriptor.id);
    final current = session.descriptor;
    if (descriptor.organizationId != current.organizationId ||
        descriptor.workspaceId != current.workspaceId ||
        descriptor.ownerSubject != current.ownerSubject ||
        descriptor.runnerResourceId != current.runnerResourceId ||
        descriptor.poolId != current.poolId ||
        descriptor.jobId != current.jobId ||
        descriptor.image != current.image ||
        descriptor.createdAt != current.createdAt ||
        descriptor.expiresAt != current.expiresAt ||
        descriptor.policyRevision < current.policyRevision ||
        descriptor.lifecycle.index < current.lifecycle.index) {
      throw const SessionProtocolException('session_scope_immutable');
    }
    session.descriptor = descriptor;
  }

  void end(String sessionId, {String reason = 'owner_stopped'}) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const SessionProtocolException('session_missing');
    }
    _endSession(session, reason);
  }

  void _endSession(_RelaySession session, String reason) {
    if (const {
      SessionLifecycle.ending,
      SessionLifecycle.cleaning,
      SessionLifecycle.cleaned,
      SessionLifecycle.failed,
    }.contains(session.descriptor.lifecycle)) {
      return;
    }
    session.expiryTimer?.cancel();
    session.descriptor = _withLifecycle(
      session.descriptor,
      SessionLifecycle.ending,
    );
    final connections = session.connections.values.toList();
    _broadcast(
      session,
      SessionFrame(
        type: 'session.end',
        id: 'end-${session.presenceRevision++}',
        payload: {'reason': reason},
      ),
    );
    for (final connection in connections) {
      unawaited(connection.close());
    }
    session.retentionTimer ??= Timer(limits.reconnectGrace, () {
      final current = _sessions[session.descriptor.id];
      if (identical(current, session) && session.connections.isEmpty) {
        _sessions.remove(session.descriptor.id);
      }
    });
  }

  void _expire(String sessionId) {
    final session = _sessions[sessionId];
    if (session != null) _endSession(session, 'expired');
  }

  void rotateSubject(String sessionId, String subject, int generation) {
    final session = _requireSession(sessionId);
    final current = session.generationBySubject[subject] ?? 0;
    if (generation < 1 || generation < current) {
      throw const SessionProtocolException('participant_generation_stale');
    }
    if (generation == current) return;
    session.generationBySubject[subject] = generation;
    for (final connection
        in session.connections.values
            .where(
              (item) =>
                  item.claims.subject == subject &&
                  item.claims.generation < generation,
            )
            .toList()) {
      connection.fail(const SessionProtocolException('participant_revoked'));
    }
  }

  @override
  Future<SessionConnection> connect({
    required Uri relayUri,
    required String grant,
    required int acknowledgedSequence,
  }) async {
    final sessionId = relayUri.pathSegments.isEmpty
        ? ''
        : relayUri.pathSegments.last;
    final session = _requireSession(sessionId);
    if (const {
      SessionLifecycle.ending,
      SessionLifecycle.cleaning,
      SessionLifecycle.cleaned,
      SessionLifecycle.failed,
    }.contains(session.descriptor.lifecycle)) {
      throw const SessionProtocolException('session_ended');
    }
    final verified = _verifyAttachGrant(grant, sessionId);
    final claims = verified.claims;
    if (!claims.capabilities.contains(SessionCapability.sessionJoin)) {
      throw const SessionProtocolException('session_join_denied');
    }
    if (verified.supervisorAuthority &&
        (claims.role != ParticipantRole.supervisor ||
            !claims.capabilities.contains(SessionCapability.sessionJoin) ||
            !claims.capabilities.contains(SessionCapability.supervisor) ||
            claims.capabilities.length != 2 ||
            claims.generation != 1 ||
            claims.policyRevision < 1 ||
            claims.jobId != session.descriptor.jobId ||
            claims.leaseId.isEmpty ||
            claims.subject != 'supervisor:${claims.leaseId}')) {
      throw const SessionProtocolException('supervisor_grant_scope_invalid');
    }
    if (claims.generation < 1 ||
        claims.policyRevision < 1 ||
        !claims.expiresAt.isAfter(claims.issuedAt) ||
        claims.expiresAt.difference(claims.issuedAt) >
            const Duration(minutes: 30) ||
        claims.expiresAt.isAfter(session.descriptor.expiresAt)) {
      throw const SessionProtocolException('grant_scope_mismatch');
    }
    _consumedTokenIds.removeWhere((_, expiry) => !expiry.isAfter(_clock()));
    if (_consumedTokenIds.containsKey(claims.tokenId)) {
      throw const SessionProtocolException('grant_replayed');
    }
    // Fleet binds its supervisor grant to the immutable launch revision.
    // Participant mutations may advance policy before placement completes;
    // the separately signed, fixed-capability supervisor cannot gain user
    // authority from an older revision. User-plane grants remain exact.
    final policyMatches = verified.supervisorAuthority
        ? claims.policyRevision <= session.descriptor.policyRevision
        : claims.policyRevision == session.descriptor.policyRevision;
    if (claims.organizationId != session.descriptor.organizationId ||
        claims.workspaceId != session.descriptor.workspaceId ||
        !policyMatches) {
      throw const SessionProtocolException('grant_scope_mismatch');
    }
    final generation = session.generationBySubject.putIfAbsent(
      claims.subject,
      () => claims.generation,
    );
    if (generation != claims.generation) {
      throw const SessionProtocolException('grant_generation_stale');
    }
    if (session.connections.length >= limits.maxParticipants) {
      throw const SessionProtocolException('participant_limit');
    }
    _consumedTokenIds[claims.tokenId] = claims.expiresAt;
    final connection = _FakeConnection(session, claims, _clock);
    session.connections[claims.tokenId] = connection;
    connection.onFrame = (frame) => _receive(session, connection, frame);
    connection.onClose = () => _detach(session, connection);
    Timer.run(() {
      _replay(session, connection, acknowledgedSequence);
      _broadcastPresence(session);
    });
    return connection;
  }

  ({SessionGrantClaims claims, bool supervisorAuthority}) _verifyAttachGrant(
    String grant,
    String sessionId,
  ) {
    try {
      return (
        claims: signer.verify(
          grant,
          audience: 'ii-session-relay',
          now: _clock(),
          sessionId: sessionId,
        ),
        supervisorAuthority: false,
      );
    } on SessionGrantException catch (primaryError) {
      final supervisor = supervisorSigner;
      if (supervisor == null) {
        throw SessionProtocolException(primaryError.code);
      }
      try {
        return (
          claims: supervisor.verify(
            grant,
            audience: 'ii-session-relay',
            now: _clock(),
            sessionId: sessionId,
          ),
          supervisorAuthority: true,
        );
      } on SessionGrantException catch (error) {
        throw SessionProtocolException(error.code);
      }
    }
  }

  _RelaySession _requireSession(String id) {
    final session = _sessions[id];
    if (session == null) {
      throw const SessionProtocolException('session_missing');
    }
    if (!session.descriptor.expiresAt.isAfter(_clock())) {
      throw const SessionProtocolException('session_expired');
    }
    return session;
  }

  Future<void> _receive(
    _RelaySession session,
    _FakeConnection source,
    SessionFrame frame,
  ) async {
    if (!session.descriptor.expiresAt.isAfter(_clock())) {
      _endSession(session, 'expired');
      throw const SessionProtocolException('session_ended');
    }
    if (const {
      SessionLifecycle.ending,
      SessionLifecycle.cleaning,
      SessionLifecycle.cleaned,
      SessionLifecycle.failed,
    }.contains(session.descriptor.lifecycle)) {
      throw const SessionProtocolException('session_ended');
    }
    final encodedBytes = utf8.encode(frame.encode()).length;
    if (encodedBytes > limits.maxFrameBytes) {
      throw const SessionProtocolException('frame_too_large');
    }
    if (!source.seenFrameIds.add(frame.id)) return;
    switch (frame.type) {
      case 'terminal.output':
        _require(source, SessionCapability.supervisor);
        parseTerminalBytes(frame.payload, limits.maxFrameBytes);
        _emitTerminalOutput(session, frame);
      case 'terminal.input':
        _require(source, SessionCapability.terminalWrite);
        final revision = (frame.payload['leaseRevision'] as num?)?.toInt();
        if (source.claims.subject != session.inputHolder ||
            revision != session.inputRevision) {
          throw const SessionProtocolException('input_lease_stale');
        }
        parseTerminalBytes(frame.payload, limits.maxFrameBytes);
        _broadcast(session, frame, capability: SessionCapability.supervisor);
      case 'terminal.resize':
        _require(source, SessionCapability.terminalWrite);
        _requireInputHolder(session, source, frame.payload);
        final columns = (frame.payload['columns'] as num?)?.toInt() ?? 0;
        final rows = (frame.payload['rows'] as num?)?.toInt() ?? 0;
        if (columns < 20 || columns > 400 || rows < 5 || rows > 200) {
          throw const SessionProtocolException('terminal_size_invalid');
        }
        _broadcast(session, frame, capability: SessionCapability.supervisor);
      case 'terminal.signal':
        _require(source, SessionCapability.terminalSignal);
        _requireInputHolder(session, source, frame.payload);
        if (!const {
          'interrupt',
          'terminate',
          'hangup',
        }.contains(frame.payload['signal'])) {
          throw const SessionProtocolException('terminal_signal_invalid');
        }
        _broadcast(session, frame, capability: SessionCapability.supervisor);
      case 'terminal.input.request':
        _require(source, SessionCapability.terminalWrite);
        _broadcast(
          session,
          SessionFrame(
            type: frame.type,
            id: frame.id,
            payload: {'subject': source.claims.subject},
          ),
          capability: SessionCapability.sessionManage,
        );
      case 'terminal.input.grant':
        _require(source, SessionCapability.sessionManage);
        final expected = (frame.payload['expectedRevision'] as num?)?.toInt();
        final subject = frame.payload['subject'];
        if (expected != session.inputRevision ||
            subject is! String ||
            !_isWritableParticipant(session, subject)) {
          throw const SessionProtocolException('input_handoff_stale');
        }
        session.inputHolder = subject;
        session.inputRevision++;
        _broadcast(
          session,
          SessionFrame(
            type: 'terminal.input.lease',
            id: frame.id,
            payload: {'subject': subject, 'revision': session.inputRevision},
          ),
        );
      case 'session.stop':
        _require(source, SessionCapability.sessionManage);
        end(session.descriptor.id);
      case 'agent.grant.install':
        _require(source, SessionCapability.sessionManage);
        if (!session.connections.values.any(
          (connection) => connection.claims.capabilities.contains(
            SessionCapability.supervisor,
          ),
        )) {
          throw const SessionProtocolException('supervisor_unavailable');
        }
        final grant = frame.payload['grant'];
        if (grant is! String || grant.isEmpty || grant.length > 8192) {
          throw const SessionProtocolException('agent_grant_invalid');
        }
        late SessionGrantClaims agent;
        try {
          agent = signer.verify(
            grant,
            audience: 'ii-session-relay',
            now: _clock(),
            sessionId: session.descriptor.id,
          );
        } on SessionGrantException catch (error) {
          throw SessionProtocolException(error.code);
        }
        final agentGeneration = session.generationBySubject.putIfAbsent(
          agent.subject,
          () => agent.generation,
        );
        if (agent.role != ParticipantRole.agent ||
            agent.organizationId != session.descriptor.organizationId ||
            agent.workspaceId != session.descriptor.workspaceId ||
            agent.policyRevision != session.descriptor.policyRevision ||
            agent.generation != agentGeneration ||
            !agent.capabilities.contains(SessionCapability.uiObserve)) {
          throw const SessionProtocolException('agent_grant_scope_invalid');
        }
        _broadcast(session, frame, capability: SessionCapability.supervisor);
      default:
        if (frame.type.startsWith('ui.')) {
          _receiveUi(session, source, frame);
          return;
        }
        throw SessionProtocolException('frame_type_unknown', frame.type);
    }
  }

  void _emitTerminalOutput(_RelaySession session, SessionFrame incoming) {
    final frame = SessionFrame(
      type: incoming.type,
      id: incoming.id,
      sequence: ++session.outputSequence,
      payload: incoming.payload,
    );
    session.replay.add(frame);
    session.replayBytes += utf8.encode(frame.encode()).length;
    while (session.replayBytes > limits.maxReplayBytes &&
        session.replay.isNotEmpty) {
      session.replayBytes -= utf8
          .encode(session.replay.removeAt(0).encode())
          .length;
      session.replayTruncated = true;
    }
    _broadcast(session, frame, capability: SessionCapability.terminalObserve);
  }

  void _replay(
    _RelaySession session,
    _FakeConnection connection,
    int acknowledgedSequence,
  ) {
    if (!connection.claims.capabilities.contains(
      SessionCapability.terminalObserve,
    )) {
      return;
    }
    if (session.replayTruncated &&
        session.replay.isNotEmpty &&
        acknowledgedSequence < (session.replay.first.sequence ?? 0) - 1) {
      connection.add(
        SessionFrame(
          type: 'terminal.replay.truncated',
          id: 'replay-${session.outputSequence}',
          payload: {'firstSequence': session.replay.first.sequence},
        ),
      );
    }
    for (final frame in session.replay.where(
      (item) => (item.sequence ?? 0) > acknowledgedSequence,
    )) {
      connection.add(frame);
    }
  }

  void _broadcast(
    _RelaySession session,
    SessionFrame frame, {
    SessionCapability? capability,
  }) {
    for (final connection in session.connections.values) {
      if (capability == null ||
          connection.claims.capabilities.contains(capability)) {
        connection.add(frame);
      }
    }
  }

  void _broadcastPresence(_RelaySession session) {
    final participants = session.connections.values
        .map(
          (item) => {
            'subject': item.claims.subject,
            'role': item.claims.role.name,
          },
        )
        .toList();
    participants.sort(
      (left, right) => left['subject']!.compareTo(right['subject']!),
    );
    _broadcast(
      session,
      SessionFrame(
        type: 'presence',
        id: 'presence-${session.presenceRevision++}',
        payload: {
          'participants': participants,
          'inputHolder': session.inputHolder,
          'inputRevision': session.inputRevision,
        },
      ),
    );
  }

  void _detach(_RelaySession session, _FakeConnection connection) {
    session.connections.remove(connection.claims.tokenId);
    session.screenshotProgress.removeWhere(
      (key, _) => key.startsWith('${connection.claims.tokenId}\u0000'),
    );
    if (connection.claims.capabilities.contains(SessionCapability.frontend) &&
        !_hasFrontend(session)) {
      session.uiState = null;
      session.uiRevision = 0;
      _broadcast(
        session,
        SessionFrame(
          type: 'ui.unavailable',
          id: 'ui-unavailable-${session.presenceRevision}',
          payload: const {},
        ),
        capability: SessionCapability.uiObserve,
      );
    }
    _broadcastPresence(session);
  }
}

/// Backwards-compatible test name for the deterministic in-memory provider.
typedef FakeSessionRelay = InMemorySessionRelay;
