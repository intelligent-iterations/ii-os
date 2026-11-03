part of 'fake_relay.dart';

void _validateSessionDescriptor(
  InteractiveSessionDescriptor descriptor,
  InteractiveSessionLimits limits,
  DateTime now,
) {
  final identities = [
    descriptor.id,
    descriptor.organizationId,
    descriptor.workspaceId,
    descriptor.ownerSubject,
    descriptor.runnerResourceId,
    descriptor.poolId,
    descriptor.jobId,
  ];
  if (identities.any(
        (value) =>
            value.isEmpty ||
            value.length > 300 ||
            value.contains(RegExp(r'[\u0000\r\n]')),
      ) ||
      descriptor.image.isEmpty ||
      descriptor.image.length > 512 ||
      descriptor.policyRevision < 1 ||
      !descriptor.expiresAt.isAfter(now) ||
      descriptor.expiresAt.difference(descriptor.createdAt) >
          limits.maxLifetime ||
      descriptor.createdAt.isAfter(now.add(const Duration(minutes: 1))) ||
      const {
        SessionLifecycle.ending,
        SessionLifecycle.cleaning,
        SessionLifecycle.cleaned,
        SessionLifecycle.failed,
      }.contains(descriptor.lifecycle)) {
    throw const SessionProtocolException('session_descriptor_invalid');
  }
}

final class _RelaySession {
  _RelaySession(this.descriptor, this.limits)
    : inputHolder = descriptor.ownerSubject;

  InteractiveSessionDescriptor descriptor;
  final InteractiveSessionLimits limits;
  final Map<String, int> generationBySubject = {};
  final Map<String, _FakeConnection> connections = {};
  final List<SessionFrame> replay = [];
  String inputHolder;
  int inputRevision = 1;
  int outputSequence = 0;
  int replayBytes = 0;
  bool replayTruncated = false;
  int presenceRevision = 1;
  int uiRevision = 0;
  SessionFrame? uiState;
  final Map<String, _ScreenshotProgress> screenshotProgress = {};
  Timer? expiryTimer;
  Timer? retentionTimer;
}

final class _ScreenshotProgress {
  _ScreenshotProgress({required this.count, required this.revision});

  final int count;
  final int revision;
  final Set<int> indices = {};
  int bytes = 0;
}

InteractiveSessionDescriptor _withLifecycle(
  InteractiveSessionDescriptor value,
  SessionLifecycle lifecycle,
) => InteractiveSessionDescriptor(
  id: value.id,
  organizationId: value.organizationId,
  workspaceId: value.workspaceId,
  ownerSubject: value.ownerSubject,
  runnerResourceId: value.runnerResourceId,
  poolId: value.poolId,
  jobId: value.jobId,
  image: value.image,
  lifecycle: lifecycle,
  policyRevision: value.policyRevision,
  createdAt: value.createdAt,
  expiresAt: value.expiresAt,
  leaseId: value.leaseId,
  runtimeIdentity: value.runtimeIdentity,
);

final class _FakeConnection implements SessionConnection {
  _FakeConnection(this.session, this.claims, this.clock);

  final _RelaySession session;
  final SessionGrantClaims claims;
  final DateTime Function() clock;
  final _controller = StreamController<SessionFrame>.broadcast(sync: true);
  final Set<String> seenFrameIds = {};
  Future<void> Function(SessionFrame frame)? onFrame;
  void Function()? onClose;
  bool _closed = false;

  @override
  Stream<SessionFrame> get frames => _controller.stream;

  void add(SessionFrame frame) {
    if (!_closed) _controller.add(frame);
  }

  void fail(Object error) {
    if (_closed) return;
    _controller.addError(error);
    close();
  }

  @override
  Future<void> send(SessionFrame frame) async {
    if (_closed) throw const SessionProtocolException('connection_closed');
    await onFrame!(frame);
  }

  @override
  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    onClose?.call();
    final hadListeners = _controller.hasListener;
    final closed = _controller.close();
    return hadListeners ? closed : Future<void>.value();
  }
}

void _require(_FakeConnection source, SessionCapability capability) {
  if (!source.claims.capabilities.contains(capability)) {
    throw SessionProtocolException('capability_denied', capability.wireName);
  }
}

void _requireInputHolder(
  _RelaySession session,
  _FakeConnection source,
  Map<String, Object?> payload,
) {
  if (source.claims.subject != session.inputHolder ||
      payload['leaseRevision'] != session.inputRevision) {
    throw const SessionProtocolException('input_lease_stale');
  }
}

bool _isWritableParticipant(_RelaySession session, String subject) =>
    session.connections.values.any(
      (item) =>
          item.claims.subject == subject &&
          item.claims.capabilities.contains(SessionCapability.terminalWrite),
    );

void _validateUiAction(Map<String, Object?> payload) {
  const allowed = {
    'activate',
    'type',
    'select',
    'scroll',
    'navigate',
    'wait_for',
  };
  final action = payload['action'];
  final target = payload['target'];
  final value = payload['value'];
  if (action is! String ||
      !allowed.contains(action) ||
      target is! String ||
      target.isEmpty ||
      target.length > 128 ||
      (value != null && (value is! String || value.length > 4096))) {
    throw const SessionProtocolException('ui_action_invalid');
  }
}
