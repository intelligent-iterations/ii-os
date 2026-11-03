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
  });

  final InteractiveSessionRepository _sessions;
  final String workspaceId;
  final String sessionId;
  final String Function() route;
  InteractiveSessionClient? _client;
  InteractiveSessionClient? _frontendClient;
  InteractiveTerminalController? terminal;
  InteractiveUiBridgeController? uiBridge;
  InteractiveSessionModel? session;
  String subject = '';
  String? errorMessage;
  bool stopping = false;

  bool get uiAccessEnabled => uiBridge?.enabled == true;
  bool get canManage =>
      subject.isNotEmpty && session?.ownerSubject == subject && !stopping;

  Future<void> start() async {
    setBusy(true);
    try {
      final previous = terminal;
      terminal = null;
      _client = null;
      previous?.dispose();
      final loaded = await _sessions.get(workspaceId, sessionId);
      final attach = await _sessions.attach(workspaceId, sessionId);
      final client = InteractiveSessionClient(
        relayUri: attach.relayUri,
        grant: attach.grant,
        transport: const WebSocketSessionTransport(),
      );
      final controller = InteractiveTerminalController(
        client: client,
        subject: attach.subject,
        canManageSession: attach.role == ParticipantRole.owner.name,
      );
      _client = client;
      terminal = controller;
      session = loaded;
      subject = attach.subject;
      await controller.connect();
      errorMessage = null;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'The terminal could not connect. Try again.',
      );
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<void> enableUiAccess({
    required bool allowAct,
    required UiActionApproval approveSensitiveAction,
    required UiScreenshotCapture captureScreenshot,
  }) async {
    final ownerClient = _client;
    if (ownerClient == null || isBusy) return;
    setBusy(true);
    try {
      const agentSubject = 'agent:codex';
      session = await _sessions.putParticipant(
        workspaceId,
        sessionId,
        agentSubject,
        ParticipantRole.agent,
      );
      final grants = await _sessions.issueUiAccess(
        workspaceId,
        sessionId,
        agentSubject: agentSubject,
        allowAct: allowAct,
      );
      await ownerClient.installAgentGrant(grants.agentGrant);
      final frontendClient = InteractiveSessionClient(
        relayUri: grants.relayUri,
        grant: grants.frontendGrant,
        transport: const WebSocketSessionTransport(),
      );
      await frontendClient.connect();
      final bridge = InteractiveUiBridgeController(
        client: frontendClient,
        route: route,
        approveSensitiveAction: approveSensitiveAction,
        captureScreenshot: captureScreenshot,
      );
      _frontendClient = frontendClient;
      uiBridge = bridge;
      await bridge.enable();
      errorMessage = null;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'Codex UI access could not be started.',
      );
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<void> disableUiAccess({bool revokeAgent = true}) async {
    Object? revokeError;
    if (revokeAgent) {
      try {
        session = await _sessions.revokeParticipant(
          workspaceId,
          sessionId,
          'agent:codex',
        );
      } on Object catch (error) {
        revokeError = error;
      }
    }
    await uiBridge?.disable();
    uiBridge?.dispose();
    uiBridge = null;
    await _frontendClient?.dispose();
    _frontendClient = null;
    if (revokeError != null) {
      errorMessage = _sessionMessage(
        revokeError,
        'Codex UI access could not be fully disabled.',
      );
    }
    notifyListeners();
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
    if (stopping) return;
    stopping = true;
    notifyListeners();
    try {
      await _sessions.stop(workspaceId, sessionId);
      await disableUiAccess(revokeAgent: false);
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
    final hadUiAuthority = uiBridge != null || _frontendClient != null;
    terminal?.dispose();
    uiBridge?.dispose();
    unawaited(_frontendClient?.dispose());
    if (hadUiAuthority) {
      unawaited(_revokeUiAuthorityOnDispose());
    }
    super.dispose();
  }

  Future<void> _revokeUiAuthorityOnDispose() async {
    try {
      await _sessions.revokeParticipant(workspaceId, sessionId, 'agent:codex');
    } on Object {
      // Closing the frontend relay connection already removes the live UI
      // surface. The server-side rotation is best-effort during widget teardown.
    }
  }
}

String _sessionMessage(Object error, String fallback) =>
    error is InteractiveSessionFailure ? error.message : fallback;
