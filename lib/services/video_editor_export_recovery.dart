import '../models/models.dart';
import '../models/workshop_rooms.dart';
import '../models/workshop_ticket_draft.dart';

const _maxTicketContextLength = 1800;

WorkshopTicketDraft? buildVideoEditorExportHealingDraft({
  required WorkspaceModel? workspace,
  required String error,
  required Iterable<String> sourceContentTypes,
  required Duration duration,
}) {
  if (workspace == null) return null;
  final room = workspace.resolvedWorkshopRooms.firstOrNull;
  if (room == null) return null;
  final repository = room.repositories
      .where(workspace.repositories.contains)
      .firstOrNull;
  final projectExists = workspace.projects.any(
    (project) => project.id == room.projectId,
  );
  if (repository == null || !projectExists) return null;

  final types =
      sourceContentTypes
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final normalizedError = error.replaceAll(RegExp(r'\s+'), ' ').trim();
  final context = _boundedContext(
    [
      'The local video editor retained the timeline after export failed.',
      'Duration: ${(duration.inMilliseconds / 1000).toStringAsFixed(3)} seconds.',
      'Source types: ${types.isEmpty ? 'unknown' : types.join(', ')}.',
      'Observed error: '
          '${normalizedError.isEmpty ? 'No technical detail was available.' : normalizedError}',
    ].join('\n'),
  );
  return WorkshopTicketDraft(
    workspaceId: workspace.id,
    roomId: room.id,
    repository: repository,
    projectId: room.projectId,
    title: 'Restore mixed-media export',
    definitionOfDone:
        'A timeline containing more than one media type renders and saves a '
        'playable export while preserving the edit after any failure.',
    howToTest:
        'In the production web editor, mix video, image, audio, and caption; '
        'move or trim a linked clip; render; save the local copy; and verify '
        'the downloaded file has playable video and audio streams.',
    context: context,
    permissionProfile: room.permissionProfile,
    permissionRef: 'dev',
  );
}

String _boundedContext(String value) {
  if (value.length <= _maxTicketContextLength) return value;
  return '${value.substring(0, _maxTicketContextLength - 1).trimRight()}\u2026';
}

extension _FirstRecoveryTargetOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
