import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/github_setup_readiness.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/production_line.dart';
import 'package:ii_os/models/workshop_ticket.dart';
import 'package:ii_os/models/workshop_pull_request.dart';
import 'package:ii_os/repositories/production_line_repository.dart';
import 'package:ii_os/repositories/workshop_repository.dart';
import 'package:ii_os/view_models/production_line_view_model.dart';

final class _StubLines implements ProductionLineRepository {
  _StubLines({this.lines = const [], this.failWith});

  List<ProductionLineModel> lines;
  Object? failWith;
  int listCalls = 0;

  @override
  Future<List<ProductionLineModel>> list(String workspaceId) async {
    listCalls++;
    if (failWith != null) throw failWith!;
    return lines;
  }

  @override
  Future<ProductionLineModel> create(String workspaceId, JsonMap body) async =>
      throw UnimplementedError();

  @override
  Future<ProductionLineModel> update(
    String workspaceId,
    String lineId,
    JsonMap body,
  ) async => throw UnimplementedError();

  @override
  Future<void> delete(String workspaceId, String lineId) async =>
      throw UnimplementedError();
}

final class _StubWorkshop implements WorkshopRepository {
  @override
  Future<void> selectProfile({
    required String workspaceId,
    required WorkshopTicket ticket,
    required String permissionProfile,
    required String permissionRef,
  }) => throw UnimplementedError();

  _StubWorkshop({this.result});

  WorkshopBoardModel? result;
  String? lastRepository;
  String? lastProjectId;
  Map<String, String>? lastStatus;
  int boardCalls = 0;

  @override
  Future<WorkshopBoardModel> board({
    required String workspaceId,
    required String projectId,
    required String repository,
  }) async {
    boardCalls++;
    lastProjectId = projectId;
    lastRepository = repository;
    return result ?? _board();
  }

  @override
  Future<GitHubSetupReadinessModel?> readiness(String workspaceId) async =>
      readinessResult;

  GitHubSetupReadinessModel? readinessResult;

  @override
  Future<void> deploy({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    String response = '',
  }) async {}

  @override
  Future<void> reset({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
  }) async {}

  @override
  Future<WorkshopPullRequestModel> pullRequest({
    required String workspaceId,
    required String itemId,
  }) async => throw UnimplementedError();

  @override
  Future<WorkshopPullRequestModel> approveAndMergePullRequest({
    required String workspaceId,
    required String itemId,
    required String expectedHeadSha,
  }) async => throw UnimplementedError();

  @override
  Future<void> setStatus({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    required String fieldId,
    required String optionId,
  }) async {
    lastStatus = {
      'itemId': itemId,
      'fieldId': fieldId,
      'optionId': optionId,
      'projectId': projectId,
    };
  }
}

void main() {
  group('load', () {
    test('reads the board through the line it resolved', () async {
      final lines = _StubLines(lines: [_line()]);
      final workshop = _StubWorkshop();
      final model = _viewModel(lines: lines, workshop: workshop);

      await model.load();

      expect(model.line?.name, 'Payments');
      // The board is fetched from the line's own binding, which is the whole
      // point of the line existing: the operator never re-picks these.
      expect(workshop.lastRepository, 'acme/payments');
      expect(workshop.lastProjectId, 'PVT_1');
      expect(model.failure, isNull);
    });

    test('reports an unavailable line without revealing whether it exists', () {
      final model = _viewModel(lines: _StubLines(lines: const []));

      return model.load().then((_) {
        expect(model.line, isNull);
        expect(model.failure, 'This production line is not available.');
      });
    });

    test(
      'surfaces a repository failure instead of silently emptying',
      () async {
        final model = _viewModel(
          lines: _StubLines(failWith: StateError('network down')),
        );

        await model.load();

        expect(model.failure, contains('network down'));
        expect(model.line, isNull);
      },
    );

    test(
      'drops a selected ticket that the reload no longer contains',
      () async {
        final model = _viewModel(lines: _StubLines(lines: [_line()]));
        await model.load();
        model.selectTicket('missing-item');

        await model.load();

        expect(model.selectedTicketId, isNull);
      },
    );
  });

  group('spinner', () {
    test('shows only before the first board, never on refresh', () async {
      final model = _viewModel(lines: _StubLines(lines: [_line()]));
      expect(model.showsInitialSpinner, isFalse, reason: 'not started yet');

      final pending = model.load();
      expect(model.showsInitialSpinner, isTrue, reason: 'first load');
      await pending;

      // R8: a refresh must not blank a board already on screen.
      final refresh = model.load();
      expect(model.showsInitialSpinner, isFalse, reason: 'refresh');
      await refresh;
    });
  });

  group('filter and selection', () {
    test('filters tickets without refetching', () async {
      final workshop = _StubWorkshop();
      final model = _viewModel(
        lines: _StubLines(lines: [_line()]),
        workshop: workshop,
      );
      await model.load();
      expect(model.visibleTickets, hasLength(1));

      model.changeFilter(WorkshopFilter.done);

      expect(model.visibleTickets, isEmpty);
      expect(workshop.boardCalls, 1, reason: 'filtering is local');
    });

    test('clears a selection the new filter hides', () async {
      final model = _viewModel(lines: _StubLines(lines: [_line()]));
      await model.load();
      model.selectTicket('PVTI_1');
      expect(model.selectedTicket, isNotNull);

      model.changeFilter(WorkshopFilter.done);

      expect(model.selectedTicketId, isNull);
    });
  });

  group('attention', () {
    test('is silent when readiness has not been read', () async {
      final model = _viewModel(
        lines: _StubLines(lines: [_line()]),
        workshop: _StubWorkshop(result: _board()),
      );
      await model.load();

      // Unknown is not unhealthy. A badge here would cry wolf on every load.
      expect(model.attention, isNull);
    });
  });

  group('setStatus', () {
    test('writes the option against the board status field', () async {
      final workshop = _StubWorkshop();
      final model = _viewModel(
        lines: _StubLines(lines: [_line()]),
        workshop: workshop,
      );
      await model.load();

      await model.setStatus(model.tickets.single, 'opt-todo');

      expect(workshop.lastStatus?['fieldId'], 'FIELD_status');
      expect(workshop.lastStatus?['optionId'], 'opt-todo');
      expect(workshop.lastStatus?['itemId'], 'PVTI_1');
      expect(workshop.boardCalls, 2, reason: 'reloads after a write');
    });

    test('does nothing when the board has no status field', () async {
      final workshop = _StubWorkshop(result: _board(statusFieldId: ''));
      final model = _viewModel(
        lines: _StubLines(lines: [_line()]),
        workshop: workshop,
      );
      await model.load();

      await model.setStatus(model.tickets.single, 'opt-todo');

      expect(workshop.lastStatus, isNull);
    });

    test('tracks busy per ticket, not for the whole board', () async {
      final model = _viewModel(lines: _StubLines(lines: [_line()]));
      await model.load();

      expect(model.ticketBusy('PVTI_1'), isFalse);
      expect(model.ticketBusy('PVTI_other'), isFalse);
    });
  });
}

ProductionLineViewModel _viewModel({
  required _StubLines lines,
  _StubWorkshop? workshop,
}) => ProductionLineViewModel(
  lines: lines,
  workshop: workshop ?? _StubWorkshop(),
  workspaceId: 'workspace-1',
  lineId: 'line-1',
);

ProductionLineModel _line() => const ProductionLineModel(
  id: 'line-1',
  name: 'Payments',
  repository: 'acme/payments',
  projectId: 'PVT_1',
  permissionProfileId: 'repository-maintainer',
  permissionRef: 'dev',
  colorToken: 'violet',
  iconToken: 'creditCard',
);

WorkshopBoardModel _board({String statusFieldId = 'FIELD_status'}) =>
    WorkshopBoardModel(
      tickets: [
        WorkshopTicket.fromProjectItem({
          'id': 'PVTI_1',
          'content': {
            '__typename': 'Issue',
            'id': 'I_1',
            'number': 12,
            'title': 'Fix the retry path',
            'state': 'OPEN',
            'url': 'https://github.com/acme/payments/issues/12',
            'repository': {'nameWithOwner': 'acme/payments'},
            'ticket': {
              'definitionOfDone': 'Retries stop doubling charges.',
              'howToTest': 'Replay the failed webhook.',
              'structured': true,
              'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
            },
          },
          'fieldValues': {'nodes': <Object?>[]},
        }, statusFieldId: statusFieldId),
      ],
      statusFieldId: statusFieldId,
      statusOptions: const [
        {'id': 'opt-todo', 'name': 'Todo'},
      ],
      supportsTodo: true,
      profiles: const [],
      profilesVerified: true,
    );
