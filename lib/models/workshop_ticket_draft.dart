/// A human-reviewable ticket brief staged by another ii-os surface.
///
/// The draft is ephemeral UI state. It is never persisted or submitted until
/// the person reviews the Software Workshop dialog and chooses Create.
final class WorkshopTicketDraft {
  const WorkshopTicketDraft({
    required this.workspaceId,
    required this.roomId,
    required this.repository,
    required this.projectId,
    required this.title,
    required this.definitionOfDone,
    required this.howToTest,
    required this.context,
    required this.permissionProfile,
    required this.permissionRef,
  });

  final String workspaceId;
  final String roomId;
  final String repository;
  final String projectId;
  final String title;
  final String definitionOfDone;
  final String howToTest;
  final String context;
  final String permissionProfile;
  final String permissionRef;
}
