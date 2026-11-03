import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/navigation/app_route_state.dart';
import 'package:ii_os/repositories/interactive_session_repository.dart';
import 'package:ii_os/screens/interactive_terminal_dialogs.dart';
import 'package:ii_os/screens/interactive_sessions_list.dart';
import 'package:ii_os/view_models/interactive_sessions_view_model.dart';

void main() {
  test('terminal session route preserves an exact session identity', () {
    final parsed = AppRouteState.fromUri(
      Uri.parse('/workspaces/workspace-1/terminal-sessions/session-1'),
    );
    expect(parsed.page, AppPage.terminalSessions);
    expect(parsed.itemId, 'session-1');
    expect(
      parsed.location,
      '/workspaces/workspace-1/terminal-sessions/session-1',
    );
  });

  testWidgets('creates a session only after an exact Fleet pool is selected', (
    tester,
  ) async {
    final repository = _Sessions();
    final model = InteractiveSessionsViewModel(
      sessions: repository,
      workspaceId: 'workspace-1',
    );
    await model.start();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveSessionsList(
            model: model,
            onSelect: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('No terminal sessions'), findsOneWidget);
    await tester.tap(find.text('New terminal session'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where this session runs'), findsOneWidget);
    expect(find.text('My host'), findsOneWidget);

    await tester.tap(find.text('My host'));
    await tester.pumpAndSettle();
    expect(repository.createdOn, 'runner-personal');
    expect(selected, 'session-1');
  });

  testWidgets('invites an exact workspace member as a bounded role', (
    tester,
  ) async {
    ({String subject, ParticipantRole role})? invite;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              invite = await inviteInteractiveParticipant(context);
            },
            child: const Text('Invite'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace member ID'),
      'member-2',
    );
    await tester.tap(find.text('Collaborator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite').last);
    await tester.pumpAndSettle();

    expect(invite?.subject, 'member-2');
    expect(invite?.role, ParticipantRole.viewer);
  });
}

final class _Sessions implements InteractiveSessionRepository {
  String? createdOn;

  @override
  Future<InteractiveSessionPage> list(String workspaceId) async =>
      const InteractiveSessionPage(
        sessions: [],
        runnerPools: [
          InteractiveRunnerPoolOption(
            resourceId: 'runner-personal',
            name: 'My host',
            providerPoolId: 'personal-owner',
            primary: true,
            maxConcurrent: 1,
          ),
        ],
      );

  @override
  Future<
    ({InteractiveSessionModel session, InteractiveSessionAttachment attach})
  >
  create(String workspaceId, {String runnerResourceId = ''}) async {
    createdOn = runnerResourceId;
    return (
      session: InteractiveSessionModel.fromJson({
        'id': 'session-1',
        'workspaceId': workspaceId,
        'ownerSubject': 'owner-1',
        'runnerResourceId': runnerResourceId,
        'poolId': 'personal-owner',
        'lifecycle': 'requested',
        'createdAt': '2026-08-25T12:00:00Z',
        'expiresAt': '2026-08-25T14:00:00Z',
        'participants': const [],
      }),
      attach: InteractiveSessionAttachment.fromJson({
        'relayUri': 'wss://relay.example/v1/connect/session-1',
        'grant': 'grant',
        'subject': 'owner-1',
        'role': 'owner',
      }),
    );
  }

  @override
  Future<InteractiveSessionModel> get(String workspaceId, String sessionId) =>
      throw UnimplementedError();

  @override
  Future<InteractiveSessionAttachment> attach(
    String workspaceId,
    String sessionId,
  ) => throw UnimplementedError();

  @override
  Future<InteractiveUiAccessGrant> issueUiAccess(
    String workspaceId,
    String sessionId, {
    required String agentSubject,
    required bool allowAct,
  }) => throw UnimplementedError();

  @override
  Future<InteractiveSessionModel> putParticipant(
    String workspaceId,
    String sessionId,
    String subject,
    ParticipantRole role,
  ) => throw UnimplementedError();

  @override
  Future<InteractiveSessionModel> revokeParticipant(
    String workspaceId,
    String sessionId,
    String subject,
  ) => throw UnimplementedError();

  @override
  Future<void> stop(String workspaceId, String sessionId) async {}
}
