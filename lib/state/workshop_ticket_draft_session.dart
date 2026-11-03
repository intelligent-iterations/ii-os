import '../models/workshop_ticket_draft.dart';

/// Holds one unsaved Workshop draft while navigation changes surfaces.
final class WorkshopTicketDraftSession {
  WorkshopTicketDraft? _pending;

  WorkshopTicketDraft? get pending => _pending;

  void stage(WorkshopTicketDraft draft) => _pending = draft;

  WorkshopTicketDraft? take({
    required String workspaceId,
    required String roomId,
    required String repository,
    required String projectId,
  }) {
    final draft = _pending;
    if (draft == null ||
        draft.workspaceId != workspaceId ||
        draft.roomId != roomId ||
        draft.repository != repository ||
        draft.projectId != projectId) {
      return null;
    }
    _pending = null;
    return draft;
  }

  void clear() => _pending = null;
}
