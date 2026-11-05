import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/interactive_session_repository.dart';
import 'package:ii_os/view_models/interactive_session_detail_view_model.dart';

void main() {
  test('dispose during initial read prevents terminal attachment', () async {
    final repository = _Sessions()..read = Completer<InteractiveSessionModel>();
    final transport = _Transport();
    final model = _model(repository, transport);
    final starting = model.start();
    await _tick();
    expect(repository.reads, 1);
    model.dispose();
    repository.read!.complete(_session);
    await starting;
    expect(repository.attachments, 0);
    expect(transport.connections, isEmpty);
    expect(model.terminal, isNull);
  });

  test('dispose during terminal connect closes the late connection', () async {
    final repository = _Sessions();
    final transport = _Transport()
      ..pendingOwner = Completer<SessionConnection>();
    final model = _model(repository, transport);
    final starting = model.start();
    await _tick();
    model.dispose();
    final connection = _Connection();
    transport.pendingOwner!.complete(connection);
    await starting;
    await _tick();
    expect(connection.closed, isTrue);
    expect(model.terminal, isNull);
  });

  for (final dispose in [true, false]) {
    test(
      '${dispose ? 'dispose' : 'disable'} during frontend connect closes late UI authority',
      () async {
        final repository = _Sessions();
        final transport = _Transport()
          ..pendingFrontend = Completer<SessionConnection>();
        final model = _model(repository, transport);
        await model.start();
        final enabling = _enable(model);
        await _tick();
        if (dispose) {
          model.dispose();
        } else {
          await model.disableUiAccess();
        }
        final connection = _Connection();
        transport.pendingFrontend!.complete(connection);
        await enabling;
        await _tick();
        expect(connection.closed, isTrue);
        expect(connection.sent, isEmpty);
        expect(model.uiBridge, isNull);
        expect(repository.revocations, greaterThan(0));
        if (!dispose) model.dispose();
      },
    );
  }

  test(
    'dispose while participant creation is pending revokes late authority',
    () async {
      final repository = _Sessions()
        ..participant = Completer<InteractiveSessionModel>();
      final transport = _Transport();
      final model = _model(repository, transport);
      await model.start();
      final enabling = _enable(model);
      model.dispose();
      repository.participant!.complete(_session);
      await enabling;
      await _tick();
      expect(repository.issued, 0);
      expect(repository.revocations, greaterThan(0));
      expect(model.uiBridge, isNull);
    },
  );

  test(
    'dispose during bridge publish immediately closes its UI surface',
    () async {
      final repository = _Sessions();
      final transport = _Transport();
      final model = _model(repository, transport);
      await model.start();
      transport.pendingFrontend = Completer<SessionConnection>();
      final enabling = _enable(model);
      await _tick();
      final connection = _Connection()..publish = Completer<void>();
      transport.pendingFrontend!.complete(connection);
      await _tick();
      model.dispose();
      await _tick();
      expect(connection.closed, isTrue);
      expect(model.uiBridge, isNull);
      connection.publish!.complete();
      await enabling;
    },
  );

  test('dispose during grant issuance never installs the late grant', () async {
    final repository = _Sessions()
      ..grants = Completer<InteractiveUiAccessGrant>();
    final transport = _Transport();
    final model = _model(repository, transport);
    await model.start();
    final enabling = _enable(model);
    await _tick();
    expect(repository.issued, 1);
    model.dispose();
    repository.grants!.complete(_grant);
    await enabling;
    expect(transport.connections.single.sent, isEmpty);
    expect(repository.revocations, greaterThan(0));
    expect(model.uiBridge, isNull);
  });

  test(
    'failed frontend connection closes it and revokes issued authority',
    () async {
      final repository = _Sessions();
      final transport = _Transport()
        ..pendingFrontend = Completer<SessionConnection>();
      final model = _model(repository, transport);
      await model.start();
      final enabling = _enable(model);
      await _tick();
      transport.pendingFrontend!.completeError(
        StateError('Synthetic connection failure'),
      );
      await enabling;
      expect(repository.revocations, greaterThan(0));
      expect(model.uiBridge, isNull);
      expect(model.uiAccessEnabled, isFalse);
      model.dispose();
    },
  );

  test(
    'active setup enables and explicit disable closes and revokes it',
    () async {
      final repository = _Sessions();
      final transport = _Transport();
      final model = _model(repository, transport);
      await model.start();
      await _enable(model);
      expect(model.uiAccessEnabled, isTrue);
      await model.disableUiAccess();
      expect(model.uiAccessEnabled, isFalse);
      expect(transport.connections.last.closed, isTrue);
      expect(repository.revocations, 1);
      model.dispose();
    },
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
Future<void> _enable(InteractiveSessionDetailViewModel model) =>
    model.enableUiAccess(
      allowAct: true,
      approveSensitiveAction: (_, _) async => false,
      captureScreenshot: (_) async =>
          throw StateError('No screenshot requested'),
    );
InteractiveSessionDetailViewModel _model(
  _Sessions repository,
  _Transport transport,
) => InteractiveSessionDetailViewModel(
  sessions: repository,
  workspaceId: 'workspace-example',
  sessionId: 'session-example',
  route: () =>
      '/workspaces/workspace-example/terminal-sessions/session-example',
  transport: transport,
);
final _session = InteractiveSessionModel.fromJson({
  'id': 'session-example',
  'workspaceId': 'workspace-example',
  'ownerSubject': 'owner-example',
  'lifecycle': 'running',
});

final _grant = InteractiveUiAccessGrant(
  relayUri: Uri.parse('wss://relay.example/session'),
  frontendGrant: 'frontend-grant',
  agentGrant: 'agent-grant',
  allowAct: true,
);

final class _Sessions implements InteractiveSessionRepository {
  Completer<InteractiveSessionModel>? read;
  Completer<InteractiveUiAccessGrant>? grants;
  int reads = 0;
  Completer<InteractiveSessionModel>? participant;
  int attachments = 0;
  int revocations = 0;
  int issued = 0;
  @override
  Future<InteractiveSessionModel> get(
    String workspaceId,
    String sessionId,
  ) async {
    reads++;
    return read == null ? _session : await read!.future;
  }

  @override
  Future<InteractiveSessionAttachment> attach(
    String workspaceId,
    String sessionId,
  ) async {
    attachments++;
    return InteractiveSessionAttachment(
      relayUri: Uri.parse('wss://relay.example/session'),
      grant: 'owner-grant',
      subject: 'owner-example',
      role: 'owner',
    );
  }

  @override
  Future<InteractiveSessionModel> putParticipant(
    String workspaceId,
    String sessionId,
    String subject,
    ParticipantRole role,
  ) async => participant == null ? _session : await participant!.future;
  @override
  Future<InteractiveUiAccessGrant> issueUiAccess(
    String workspaceId,
    String sessionId, {
    required String agentSubject,
    required bool allowAct,
  }) async {
    issued++;
    return grants == null ? _grant : await grants!.future;
  }

  @override
  Future<InteractiveSessionModel> revokeParticipant(
    String workspaceId,
    String sessionId,
    String subject,
  ) async {
    revocations++;
    return _session;
  }

  @override
  Future<void> stop(String workspaceId, String sessionId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Transport implements SessionTransport {
  Completer<SessionConnection>? pendingOwner;
  Completer<SessionConnection>? pendingFrontend;
  final connections = <_Connection>[];
  @override
  Future<SessionConnection> connect({
    required Uri relayUri,
    required String grant,
    required int acknowledgedSequence,
  }) async {
    final pending = grant == 'owner-grant' ? pendingOwner : pendingFrontend;
    if (pending != null) return pending.future;
    final connection = _Connection();
    connections.add(connection);
    return connection;
  }
}

final class _Connection implements SessionConnection {
  final controller = StreamController<SessionFrame>.broadcast();
  final sent = <SessionFrame>[];
  bool closed = false;
  Completer<void>? publish;
  @override
  Stream<SessionFrame> get frames => controller.stream;
  @override
  Future<void> send(SessionFrame frame) async {
    sent.add(frame);
    if (frame.type == 'ui.state') await publish?.future;
  }

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}
