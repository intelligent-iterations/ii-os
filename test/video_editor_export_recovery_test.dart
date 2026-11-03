import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/workshop_room.dart';
import 'package:ii_os/models/workshop_ticket_draft.dart';
import 'package:ii_os/services/video_editor_export_recovery.dart';
import 'package:ii_os/state/app_controller.dart';

void main() {
  test('builds a bounded Workshop draft for the matching room', () {
    const workspace = WorkspaceModel(
      id: 'workspace-1',
      name: 'Demo',
      environment: 'dev',
      githubInstallationId: 42,
      repositories: ['acme-co/example-app'],
      projects: [
        ProjectConnection(
          id: 'project-7',
          number: 7,
          owner: 'acme-co',
          title: 'Example tasks',
        ),
      ],
      workflows: [],
      artifactStorage: null,
      workshopRooms: [
        WorkshopRoomModel(
          id: 'main',
          name: 'Main room',
          color: 'cyan',
          repositories: ['acme-co/example-app'],
          projectId: 'project-7',
          permissionProfile: 'repository-maintainer',
        ),
      ],
    );

    final draft = buildVideoEditorExportHealingDraft(
      workspace: workspace,
      error:
          '  FFmpeg\nfailed   while composing. '
          '${List.filled(4000, 'x').join()}',
      sourceContentTypes: const [
        'video/mp4',
        'image/png',
        'audio/wav',
        'video/mp4',
      ],
      duration: const Duration(seconds: 3),
    );

    expect(draft, isNotNull);
    expect(draft!.roomId, 'main');
    expect(draft.repository, 'acme-co/example-app');
    expect(draft.projectId, 'project-7');
    expect(draft.title, 'Restore mixed-media export');
    expect(draft.definitionOfDone, contains('playable export'));
    expect(draft.howToTest, contains('video, image, audio, and caption'));
    expect(draft.context, contains('FFmpeg failed while composing.'));
    expect(draft.context, contains('audio/wav, image/png, video/mp4'));
    expect(draft.context.length, lessThanOrEqualTo(1800));
    expect(draft.permissionProfile, 'repository-maintainer');
    expect(draft.permissionRef, 'dev');
  });

  test('stages one draft until the matching Workshop consumes it', () {
    final controller = AppController();
    addTearDown(controller.dispose);
    const draft = WorkshopTicketDraft(
      workspaceId: 'workspace-1',
      roomId: 'main',
      repository: 'acme-co/example-app',
      projectId: 'project-7',
      title: 'Restore mixed-media export',
      definitionOfDone: 'Done',
      howToTest: 'Test',
      context: 'Error',
      permissionProfile: 'repository-maintainer',
      permissionRef: 'dev',
    );

    controller.workshopTicketDrafts.stage(draft);
    expect(
      controller.workshopTicketDrafts.take(
        workspaceId: 'another-workspace',
        roomId: 'main',
        repository: 'acme-co/example-app',
        projectId: 'project-7',
      ),
      isNull,
    );
    expect(controller.workshopTicketDrafts.pending, same(draft));
    expect(
      controller.workshopTicketDrafts.take(
        workspaceId: 'workspace-1',
        roomId: 'main',
        repository: 'acme-co/example-app',
        projectId: 'project-7',
      ),
      same(draft),
    );
    expect(controller.workshopTicketDrafts.pending, isNull);
  });

  test('returns no draft when the workspace has no Workshop target', () {
    const workspace = WorkspaceModel(
      id: 'workspace-1',
      name: 'Demo',
      environment: 'dev',
      githubInstallationId: null,
      repositories: [],
      projects: [],
      workflows: [],
      artifactStorage: null,
    );

    expect(
      buildVideoEditorExportHealingDraft(
        workspace: workspace,
        error: 'failed',
        sourceContentTypes: const [],
        duration: Duration.zero,
      ),
      isNull,
    );
  });
}
