import 'package:stacked/stacked.dart';

import '../models/agent_permission.dart';
import '../models/models.dart';
import '../models/production_line.dart';
import '../models/workshop_ticket.dart';
import '../repositories/production_line_repository.dart';
import '../repositories/workshop_repository.dart';

/// Busy keys, so the board load and a per-ticket mutation can be told apart by
/// the view instead of sharing one boolean.
abstract final class ProductionLineBusy {
  static const board = 'board';
  static const status = 'status';
}

/// State for one production line's page.
///
/// Constructor-injected so a unit test can drive it with stub repositories and
/// no widget tree.
final class ProductionLineViewModel extends BaseViewModel {
  ProductionLineViewModel({
    required this._lines,
    required this._workshop,
    required this.workspaceId,
    required this.lineId,
    this.filter = WorkshopFilter.active,
  });

  final ProductionLineRepository _lines;
  final WorkshopRepository _workshop;

  final String workspaceId;
  final String lineId;

  ProductionLineModel? line;
  WorkshopBoardModel? board;
  WorkshopFilter filter;
  String? selectedTicketId;

  /// What went wrong, ready to render. `null` when the last attempt succeeded.
  String? get failure => hasError ? '$modelError' : null;

  bool get loadingBoard => busy(ProductionLineBusy.board);

  /// True only before anything has ever loaded.
  ///
  /// The spinner is gated on the absence of data rather than on busy, so a
  /// refresh never blanks a board the operator is already reading.
  bool get showsInitialSpinner => loadingBoard && board == null;

  List<WorkshopTicket> get tickets => board?.tickets ?? const [];

  List<WorkshopTicket> get visibleTickets =>
      tickets.where(filter.includes).toList();

  WorkshopTicket? get selectedTicket => visibleTickets
      .where((ticket) => ticket.itemId == selectedTicketId)
      .firstOrNull;

  List<JsonMap> get statusOptions => board?.statusOptions ?? const [];

  List<AgentPermissionModel> get profiles => board?.profiles ?? const [];

  /// Whether this line's repository passed its live agent readiness checks.
  bool get automationReady =>
      line != null && (board?.readiness?.readyFor(line!.repository) ?? false);

  String get automationDetail {
    final readiness = board?.readiness;
    if (readiness == null) {
      return 'Run the repository checks before deploying agent work.';
    }
    if (!readiness.workspace.ready) {
      return 'This repository may be configured, but the workspace-level '
          'human-started deployment queue is not running.';
    }
    if (automationReady) {
      return 'Live checks passed for the GitHub App, workflow, committed '
          'permission profile, protected environment, and Codex.';
    }
    return 'Finish the remaining repository setup before a ticket can be '
        'deployed.';
  }

  /// What the sidebar badge reports, or null when the line is healthy.
  String? get attention {
    if (line == null) return null;
    if (board?.readiness == null) return null;
    return automationReady ? null : automationDetail;
  }

  WorkshopTicketReadiness readinessFor(WorkshopTicket ticket) =>
      ticket.readiness(
        profiles: profiles,
        permissionProfilesVerified: board?.profilesVerified ?? false,
        projectSupportsTodo: board?.supportsTodo ?? false,
        automationReady: automationReady,
        automationDetail: automationDetail,
      );

  Future<void> load() async {
    setError(null);
    setBusyForObject(ProductionLineBusy.board, true);
    notifyListeners();
    try {
      final all = await _lines.list(workspaceId);
      final selected = all.where((item) => item.id == lineId).firstOrNull;
      if (selected == null) {
        // The list route already filtered by visibility, so an absent line is
        // either gone or never ours. Say the same thing either way, so this
        // cannot be used to probe for which lines exist.
        setError('This production line is not available.');
        line = null;
        board = null;
        return;
      }
      line = selected;
      board = await _workshop.board(
        workspaceId: workspaceId,
        projectId: selected.projectId,
        repository: selected.repository,
      );
      if (selectedTicketId != null &&
          !visibleTickets.any((ticket) => ticket.itemId == selectedTicketId)) {
        selectedTicketId = null;
      }
    } on Object catch (failure) {
      setError(failure);
    } finally {
      setBusyForObject(ProductionLineBusy.board, false);
      notifyListeners();
    }
  }

  void selectTicket(String? itemId) {
    selectedTicketId = itemId;
    notifyListeners();
  }

  void changeFilter(WorkshopFilter value) {
    filter = value;
    if (selectedTicket == null) selectedTicketId = null;
    notifyListeners();
  }

  bool ticketBusy(String itemId) =>
      busy('${ProductionLineBusy.status}:$itemId');

  Future<void> setStatus(WorkshopTicket ticket, String optionId) async {
    final fieldId = board?.statusFieldId ?? '';
    final projectId = line?.projectId;
    if (fieldId.isEmpty || projectId == null) return;
    final key = '${ProductionLineBusy.status}:${ticket.itemId}';
    setBusyForObject(key, true);
    notifyListeners();
    try {
      await _workshop.setStatus(
        repository: ticket.repository,
        workspaceId: workspaceId,
        projectId: projectId,
        itemId: ticket.itemId,
        fieldId: fieldId,
        optionId: optionId,
      );
      await load();
    } on Object catch (failure) {
      setError(failure);
    } finally {
      setBusyForObject(key, false);
      notifyListeners();
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
