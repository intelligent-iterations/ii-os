part of 'fake_relay.dart';

extension on InMemorySessionRelay {
  void _receiveUi(
    _RelaySession session,
    _FakeConnection source,
    SessionFrame frame,
  ) {
    switch (frame.type) {
      case 'ui.state':
        _require(source, SessionCapability.frontend);
        final revision = (frame.payload['revision'] as num?)?.toInt() ?? 0;
        final nodes = frame.payload['nodes'];
        if (revision <= session.uiRevision ||
            nodes is! List<Object?> ||
            nodes.length > limits.maxSemanticNodes) {
          throw const SessionProtocolException('ui_state_invalid');
        }
        session.uiRevision = revision;
        session.uiState = frame;
        _broadcast(session, frame, capability: SessionCapability.uiObserve);
      case 'ui.observe':
        _require(source, SessionCapability.uiObserve);
        final state = session.uiState;
        source.add(
          state == null
              ? SessionFrame(
                  type: 'ui.unavailable',
                  id: frame.id,
                  payload: const {},
                )
              : SessionFrame(
                  type: state.type,
                  id: frame.id,
                  payload: state.payload,
                ),
        );
      case 'ui.screenshot.request':
        _require(source, SessionCapability.uiObserve);
        if (!_hasFrontend(session)) {
          throw const SessionProtocolException('ui_frontend_unavailable');
        }
        _broadcast(session, frame, capability: SessionCapability.frontend);
      case 'ui.screenshot.chunk':
        _receiveScreenshotChunk(session, source, frame);
      case 'ui.action':
        _require(source, SessionCapability.uiAct);
        if (!_hasFrontend(session)) {
          throw const SessionProtocolException('ui_frontend_unavailable');
        }
        final expected = (frame.payload['expectedRevision'] as num?)?.toInt();
        if (expected != session.uiRevision) {
          throw const SessionProtocolException('ui_revision_stale');
        }
        _validateUiAction(frame.payload);
        _broadcast(session, frame, capability: SessionCapability.frontend);
      case 'ui.action.result':
        _require(source, SessionCapability.frontend);
        _broadcast(session, frame, capability: SessionCapability.uiObserve);
      default:
        throw SessionProtocolException('frame_type_unknown', frame.type);
    }
  }

  void _receiveScreenshotChunk(
    _RelaySession session,
    _FakeConnection source,
    SessionFrame frame,
  ) {
    _require(source, SessionCapability.frontend);
    final revision = (frame.payload['revision'] as num?)?.toInt();
    final index = (frame.payload['index'] as num?)?.toInt() ?? -1;
    final count = (frame.payload['count'] as num?)?.toInt() ?? 0;
    final screenshotId = frame.payload['screenshotId'];
    final mimeType = frame.payload['mimeType'];
    final bytes = parseTerminalBytes(frame.payload, 44 * 1024);
    if (revision != session.uiRevision) {
      throw const SessionProtocolException('ui_revision_stale');
    }
    if (index < 0 ||
        count < 1 ||
        count > 32 ||
        index >= count ||
        screenshotId is! String ||
        screenshotId.length > 128 ||
        mimeType != 'image/png') {
      throw const SessionProtocolException('ui_screenshot_invalid');
    }
    final progressKey = '${source.claims.tokenId}\u0000$screenshotId';
    var progress = session.screenshotProgress[progressKey];
    if (progress == null) {
      if (session.screenshotProgress.keys
              .where((key) => key.startsWith('${source.claims.tokenId}\u0000'))
              .length >=
          4) {
        throw const SessionProtocolException('ui_screenshot_limit');
      }
      progress = _ScreenshotProgress(count: count, revision: revision!);
      session.screenshotProgress[progressKey] = progress;
    }
    if (progress.count != count ||
        progress.revision != revision ||
        !progress.indices.add(index)) {
      throw const SessionProtocolException('ui_screenshot_invalid');
    }
    progress.bytes += bytes.length;
    if (progress.bytes > limits.maxScreenshotBytes) {
      session.screenshotProgress.remove(progressKey);
      throw const SessionProtocolException('ui_screenshot_too_large');
    }
    if (progress.indices.length == count) {
      session.screenshotProgress.remove(progressKey);
    }
    _broadcast(session, frame, capability: SessionCapability.uiObserve);
  }
}

bool _hasFrontend(_RelaySession session) => session.connections.values.any(
  (item) => item.claims.capabilities.contains(SessionCapability.frontend),
);
