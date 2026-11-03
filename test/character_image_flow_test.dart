import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/character_detail_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('legacy image drafts bypass the interview and remain retryable', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#image-edit-qwen-2511'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'characters.write', 'jobs.trigger'},
          capabilities: {'characters.write', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: CharacterDetailScreen(
            controller: controller,
            character: const CharacterModel(
              id: 'image-character-1',
              workspaceId: 'workspace-1',
              name: 'Reference subject',
              creationMode: 'image',
              sourceAssetId: 'source-1',
              answers: {},
              prompt: '',
              status: 'draft',
              thumbnailUrl: null,
              createdAt: null,
              updatedAt: null,
            ),
            canWrite: true,
            initialImages: const [],
            onSaved: (_) {},
            onDeleted: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('character-essentials')), findsNothing);
    expect(find.text('Shape the character'), findsNothing);
    expect(find.text('Full-body generation prompt'), findsNothing);
    final generate = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate full-body sheet'),
    );
    expect(generate.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active image generation can be left without a framework error', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#image-edit-qwen-2511'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'characters.write', 'jobs.trigger'},
          capabilities: {'characters.write', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: CharacterDetailScreen(
          controller: controller,
          character: const CharacterModel(
            id: 'image-character-1',
            workspaceId: 'workspace-1',
            name: 'Reference subject',
            creationMode: 'image',
            sourceAssetId: 'source-1',
            answers: {},
            prompt: '',
            status: 'draft',
            thumbnailUrl: null,
            lastBodyGenerationJobId: 'job-1',
            lastBodyGenerationStatus: 'dispatched',
            createdAt: null,
            updatedAt: null,
          ),
          canWrite: true,
          initialBodyGeneration: const {
            'jobId': 'job-1',
            'status': 'dispatched',
            'runtimeEstimate': {
              'estimatedSeconds': 50,
              'hardware': '24 GB GPU',
              'measuredAt': '2026-08-24',
              'baselineRuntimeSeconds': 50,
            },
          },
          initialImages: const [],
          onSaved: (_) {},
          onDeleted: () {},
          onClose: () {},
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('character-selected-sheet-generating')),
      findsOneWidget,
    );
    expect(find.textContaining('About 1 minute'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });
}
