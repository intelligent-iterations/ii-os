import 'dart:async';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_interactive_sessions_flutter/ii_interactive_sessions_flutter.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/interactive_session_repository.dart';

final class InteractiveSessionDetailViewModel extends BaseViewModel {
  InteractiveSessionDetailViewModel({
    required this._sessions,
    required this.workspaceId,
    required this.sessionId,
    required this.route,
    this.transport = const WebSocketSessionTransport(),
  });

  final InteractiveSessionRepository _sessions;
  final String workspaceId;
  final String sessionId;
  final String Function() route;
  final SessionTransport transport;
  InteractiveSessionClient? _client;
  InteractiveSessionClient? _frontendClient;
  InteractiveTerminalController? terminal;
  InteractiveUiBridgeController? uiBridge;
  InteractiveSessionModel? session;
  String subject = '';
  String? errorMessage;
  bool stopping = false;
  bool _disposed = false;
  bool _uiAuthority = false;
  bool _disablingUi = false;
  int _startGeneration = 0;
  int _uiGeneration = 0;

  bool get uiAccessEnabled => uiBridge?.enabled == true;
  bool get canManage =>
      !_disposed &&
      subject.isNotEmpty &&
      session?.ownerSubject == subject &&
      !stopping;

  Future<void> start() async {
    if (_disposed || isBusy || _disablingUi) return;
    final generation = ++_startGeneration;
    bool current() => !_disposed && generation == _startGeneration;
    setBusy(true);
    InteractiveTerminalController? created;
    var adopted = false;
    try {
      await disableUiAccess();
      if (!current()) return;
      terminal?.dispose();
      terminal = null;
      _client = null;
      final loaded = await _sessions.get(workspaceId, sessionId);
      if (!current()) return;
      final attach = await _sessions.attach(workspaceId, sessionId);
      if (!current()) return;
      final client = InteractiveSessionClient(
        relayUri: attach.relayUri,
        grant: attach.grant,
        transport: transport,
      );
      created = InteractiveTerminalController(
        client: client,
        subject: attach.subject,
        canManageSession: attach.role == ParticipantRole.owner.name,
      );
      await created.connect();
      if (!current()) return;
      _client = client;
      terminal = created;
      session = loaded;
      subject = attach.subject;
      adopted = true;
      errorMessage = null;
    } on Object catch (error) {
      if (current()) {
        errorMessage = _sessionMessage(
          error,
          'The terminal could not connect. Try again.',
        );
      }
    } finally {
      if (!adopted && created != null) {
        await created.shutdown();
        created.dispose();
      }
      if (current()) {
        setBusy(false);
        notifyListeners();
      }
    }
  }

  Future<void> enableUiAccess({
    required bool allowAct,
    required UiActionApproval approveSensitiveAction,
    required UiScreenshotCapture captureScreenshot,
  }) async {
    final ownerClient = _client;
    if (_disposed ||
        ownerClient == null ||
        isBusy ||
        _uiAuthority ||
        _disablingUi) {
      return;
    }
    final generation = ++_uiGeneration;
    bool current() => !_disposed && generation == _uiGeneration;
    _uiAuthority = true;
    setBusy(true);
    InteractiveSessionClient? created;
    InteractiveUiBridgeController? bridge;
    var adopted = false;
    try {
      final updated = await _sessions.putParticipant(
        workspaceId,
        sessionId,
        'agent:codex',
        ParticipantRole.agent,
      );
      if (!current()) return;
      session = updated;
      final grants = await _sessions.issueUiAccess(
        workspaceId,
        sessionId,
        agentSubject: 'agent:codex',
        allowAct: allowAct,
      );
      if (!current()) return;
      await ownerClient.installAgentGrant(grants.agentGrant);
      if (!current()) return;
      created = InteractiveSessionClient(
        relayUri: grants.relayUri,
        grant: grants.frontendGrant,
        transport: transport,
      );
      // Keep local ownership until connection and bridge setup both finish.
      // Cancellation closes even a connection returned after widget teardown.
      await created.connect();
      if (!current()) return;
      bridge = InteractiveUiBridgeController(
        client: created,
        route: route,
        approveSensitiveAction: approveSensitiveAction,
        captureScreenshot: captureScreenshot,
      );
      _frontendClient = created;
      uiBridge = bridge;
      await bridge.enable();
      if (!current()) return;
      adopted = true;
      errorMessage = null;
    } on Object catch (error) {
      if (current()) {
        errorMessage = _sessionMessage(
          error,
          'Codex UI access could not be started.',
        );
      }
    } finally {
      if (!adopted) {
        await _discardUiSetup(bridge, created);
      }
      if (!_disposed) {
        setBusy(false);
        notifyListeners();
      }
    }
  }

  Future<void> _discardUiSetup(
    InteractiveUiBridgeController? bridge,
    InteractiveSessionClient? client,
  ) async {
    if (bridge != null && identical(uiBridge, bridge)) {
      uiBridge = null;
      await bridge.disable();
      bridge.dispose();
    }
    if (identical(_frontendClient, client)) _frontendClient = null;
    await _closeClient(client);
    // Repeat after pending server calls settle: an earlier teardown
    // revocation may have raced participant/grant creation on the server.
    await _revokeUiAuthority();
    _uiAuthority = false;
  }

  Future<void> disableUiAccess({bool revokeAgent = true}) async {
    if (_disablingUi) return;
    _disablingUi = true;
    ++_uiGeneration;
    final bridge = uiBridge;
    final client = _frontendClient;
    final hadAuthority = _uiAuthority;
    uiBridge = null;
    _frontendClient = null;
    _uiAuthority = false;
    try {
      // Close the local surface before waiting for server-side revocation.
      if (bridge != null) {
        await bridge.disable();
        bridge.dispose();
      }
      await _closeClient(client);
      if (revokeAgent && hadAuthority) await _revokeUiAuthority();
    } finally {
      _disablingUi = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> invite(String invitedSubject, ParticipantRole role) async {
    if (!canManage || isBusy) return false;
    setBusy(true);
    try {
      session = await _sessions.putParticipant(
        workspaceId,
        sessionId,
        invitedSubject,
        role,
      );
      errorMessage = null;
      return true;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'That person could not be invited.',
      );
      return false;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<bool> revoke(String revokedSubject) async {
    if (!canManage || isBusy) return false;
    setBusy(true);
    try {
      session = await _sessions.revokeParticipant(
        workspaceId,
        sessionId,
        revokedSubject,
      );
      errorMessage = null;
      return true;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'That participant could not be removed.',
      );
      return false;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_disposed || stopping) return;
    stopping = true;
    notifyListeners();
    try {
      await disableUiAccess(revokeAgent: false);
      await _sessions.stop(workspaceId, sessionId);
      errorMessage = null;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'The terminal session could not be stopped.',
      );
    } finally {
      stopping = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_startGeneration;
    ++_uiGeneration;
    terminal?.dispose();
    terminal = null;
    _client = null;
    final bridge = uiBridge;
    uiBridge = null;
    bridge?.dispose();
    final client = _frontendClient;
    _frontendClient = null;
    unawaited(_closeClient(client));
    if (_uiAuthority) unawaited(_revokeUiAuthority());
    _uiAuthority = false;
    super.dispose();
  }

  Future<void> _closeClient(InteractiveSessionClient? client) async {
    try {
      await client?.dispose();
    } on Object {
      // Continue revocation even when the transport cannot confirm closure.
    }
  }

  Future<void> _revokeUiAuthority() async {
    try {
      final updated = await _sessions.revokeParticipant(
        workspaceId,
        sessionId,
        'agent:codex',
      );
      if (!_disposed) session = updated;
    } on Object {
      // Local relay connections are closed even if server rotation fails.
      if (!_disposed) {
        errorMessage = 'Codex UI access could not be fully disabled.';
      }
    }
  }
}

String _sessionMessage(Object error, String fallback) =>
    error is InteractiveSessionFailure ? error.message : fallback;
