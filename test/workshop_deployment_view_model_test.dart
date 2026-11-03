import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/github_setup_readiness.dart';
import 'package:ii_os/models/workshop_pull_request.dart';
import 'package:ii_os/models/workshop_ticket.dart';
import 'package:ii_os/repositories/workshop_repository.dart';
import 'package:ii_os/view_models/workshop_deployment_view_model.dart';

final class _RecordingWorkshop implements WorkshopRepository {
  final dispatch = Completer<void>();
  final resetDispatch = Completer<void>();
  int deployCalls = 0;
  int resetCalls = 0;
  int profileSelectionCalls = 0;
  String? response;
  String? permissionProfile;
  String? selectedRepository;

  @override
  Future<void> selectProfile({
    required String workspaceId,
    required WorkshopTicket ticket,
    required String permissionProfile,
    required String permissionRef,
  }) async {
    profileSelectionCalls++;
    this.permissionProfile = permissionProfile;
  }

  @override
  Future<void> deploy({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    String response = '',
  }) {
    deployCalls++;
    selectedRepository = repository;
    this.response = response;
    return dispatch.future;
  }

  @override
  Future<void> reset({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
  }) {
    resetCalls++;
    return resetDispatch.future;
  }

  @override
  Future<WorkshopBoardModel> board({
    required String workspaceId,
    required String projectId,
    required String repository,
  }) => throw UnimplementedError();

  @override
  Future<GitHubSetupReadinessModel?> readiness(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<void> setStatus({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    required String fieldId,
    required String optionId,
  }) => throw UnimplementedError();

  @override
  Future<WorkshopPullRequestModel> pullRequest({
    required String workspaceId,
    required String itemId,
  }) => throw UnimplementedError();

  @override
  Future<WorkshopPullRequestModel> approveAndMergePullRequest({
    required String workspaceId,
    required String itemId,
    required String expectedHeadSha,
  }) => throw UnimplementedError();
}

void main() {
  test(
    'deployment is visibly pending until the refreshed board confirms it',
    () async {
      final repository = _RecordingWorkshop();
      final model = WorkshopDeploymentViewModel(repository);

      final operation = model.deploy(
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        ticket: _ticket,
        response: 'Keep the existing brief.',
      );

      expect(model.deploying(_ticket.itemId), isTrue);
      expect(repository.deployCalls, 1);
      expect(repository.response, 'Keep the existing brief.');
      expect(repository.selectedRepository, _ticket.repository);

      repository.dispatch.complete();
      await operation;

      expect(
        model.deploying(_ticket.itemId),
        isTrue,
        reason: 'the old board must not flash a Deploy action before refresh',
      );
      model.confirm(_ticket.itemId);
      expect(model.deploying(_ticket.itemId), isFalse);
    },
  );

  test(
    'a rejected deployment restores the action and exposes the failure',
    () async {
      final repository = _RecordingWorkshop();
      final model = WorkshopDeploymentViewModel(repository);
      final operation = model.deploy(
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        ticket: _ticket,
      );
      final assertion = expectLater(operation, throwsA(isA<StateError>()));

      repository.dispatch.completeError(StateError('dispatch refused'));
      await assertion;

      expect(model.deploying(_ticket.itemId), isFalse);
      expect(model.hasError, isTrue);
    },
  );

  test('selected model is saved before readiness is rechecked', () async {
    final repository = _RecordingWorkshop();
    final model = WorkshopDeploymentViewModel(repository);

    await model.selectProfile(
      workspaceId: 'workspace-1',
      ticket: _ticket,
      permissionProfile: 'qwen38-repository-maintainer',
      permissionRef: 'dev',
    );

    expect(repository.profileSelectionCalls, 1);
    expect(repository.permissionProfile, 'qwen38-repository-maintainer');
  });

  test(
    'reset stays pending until the fresh board confirms a clean ticket',
    () async {
      final repository = _RecordingWorkshop();
      final model = WorkshopDeploymentViewModel(repository);

      final operation = model.reset(
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        ticket: _ticket,
      );

      expect(model.resetting(_ticket.itemId), isTrue);
      expect(repository.resetCalls, 1);
      repository.resetDispatch.complete();
      await operation;
      expect(model.resetting(_ticket.itemId), isTrue);
      model.confirmReset(_ticket.itemId);
      expect(model.resetting(_ticket.itemId), isFalse);
    },
  );
}

const _ticket = WorkshopTicket(
  itemId: 'item-42',
  issueId: 'issue-42',
  number: 42,
  title: 'Keep queue feedback visible',
  repository: 'acme-co/example-app',
  issueState: 'OPEN',
  url: 'https://github.com/acme-co/example-app/issues/42',
  status: 'Todo',
  statusOptionId: 'todo',
  definitionOfDone: 'Queue feedback appears immediately.',
  howToTest: 'Deploy a ticket from the live Workshop.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: '',
  structured: true,
  agentReady: false,
  canDeploy: true,
);
