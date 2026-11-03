import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/character_detail_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/character_sheet_edit_composer.dart';

void main() {
  for (final creationMode in const ['scratch', 'image']) {
    testWidgets(
      '$creationMode character sheets separate whole-sheet and area editing',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = AppController()
          ..selectedAccess = const WorkspaceAccess(
            workspace: WorkspaceModel(
              id: 'workspace-1',
              name: 'Media operations',
              environment: 'dev',
              githubInstallationId: 12,
              repositories: ['acme/media'],
              projects: [],
              workflows: [
                'acme/media#image-edit-qwen-2511',
                'acme/media#image-inpaint-qwen',
              ],
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
                character: CharacterModel(
                  id: '$creationMode-character',
                  workspaceId: 'workspace-1',
                  name: 'Character',
                  creationMode: creationMode,
                  sourceAssetId: creationMode == 'image' ? 'source-1' : null,
                  answers: const {},
                  prompt: 'Character prompt',
                  bodyPrompt: 'Body prompt',
                  status: 'ready',
                  thumbnailUrl: null,
                  createdAt: null,
                  updatedAt: null,
                ),
                canWrite: true,
                initialImages: const [
                  CharacterImageModel(
                    jobId: 'sheet-job',
                    path: 'character-sheet.png',
                    generation: '1',
                    contentType: 'image/png',
                    url: 'https://example.invalid/character-sheet.png',
                    selected: true,
                    createdAt: null,
                  ),
                ],
                onSaved: (_) {},
                onDeleted: () {},
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Tweak entire sheet'), findsOneWidget);
        expect(find.text('Edit an area'), findsOneWidget);
        expect(find.textContaining('Inpaint'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('character-edit-area-open')),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('character-sheet-edit-composer')),
          findsOneWidget,
        );
        expect(find.text('Edit an area'), findsOneWidget);
        expect(find.text('Select area'), findsOneWidget);
        expect(find.text('Brush'), findsOneWidget);
        expect(find.text('Erase'), findsOneWidget);
        expect(find.text('What should change here?'), findsNothing);
      },
    );
  }

  testWidgets('area editor submits every disconnected selected area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prompt = TextEditingController(
      text: 'Make the chest marking consistent across every view.',
    );
    addTearDown(prompt.dispose);
    List<Rect>? submitted;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CharacterSheetEditComposer(
              mode: CharacterSheetEditMode.area,
              image: const CharacterImageModel(
                jobId: 'sheet-job',
                path: 'character-sheet.png',
                generation: '1',
                contentType: 'image/png',
                url: '',
                selected: true,
                createdAt: null,
              ),
              controller: prompt,
              enabled: true,
              busy: false,
              onChanged: (_) {},
              onSubmit: (masks) => submitted = masks,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('inpaint-mask-surface'));
    var origin = tester.getTopLeft(surface);
    await tester.dragFrom(
      origin + const Offset(80, 80),
      const Offset(120, 100),
    );
    await tester.pump();
    expect(find.text('What should change here?'), findsOneWidget);
    origin = tester.getTopLeft(surface);
    await tester.dragFrom(
      origin + const Offset(500, 200),
      const Offset(120, 100),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('character-edit-submit')));
    expect(submitted, hasLength(2));
  });

  testWidgets('whole-sheet editor needs no area selection', (tester) async {
    final prompt = TextEditingController(text: 'Clean up the line work.');
    addTearDown(prompt.dispose);
    List<Rect>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CharacterSheetEditComposer(
              mode: CharacterSheetEditMode.wholeSheet,
              image: const CharacterImageModel(
                jobId: 'sheet-job',
                path: 'character-sheet.png',
                generation: '1',
                contentType: 'image/png',
                url: '',
                selected: true,
                createdAt: null,
              ),
              controller: prompt,
              enabled: true,
              busy: false,
              onChanged: (_) {},
              onSubmit: (masks) => submitted = masks,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tweak entire sheet'), findsOneWidget);
    expect(find.byKey(const ValueKey('inpaint-mask-surface')), findsNothing);
    expect(find.text('What should change?'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('character-edit-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('character-edit-submit')));
    expect(submitted, isEmpty);
  });

  testWidgets('edit review defaults to after and offers every decision', (
    tester,
  ) async {
    var kept = false;
    var retried = false;
    var discarded = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CharacterSheetEditReview(
              mode: CharacterSheetEditMode.area,
              before: _image('before.png', '1'),
              after: _image('after.png', '2'),
              prompt: 'Make the chest patch smaller.',
              busy: false,
              onKeep: () => kept = true,
              onTryAgain: () => retried = true,
              onDiscard: () => discarded = true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('character-edit-review-after')),
      findsOneWidget,
    );
    await tester.tap(find.text('Before'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('character-edit-review-before')),
      findsOneWidget,
    );
    for (final label in const ['Try again', 'Discard', 'Keep this edit']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
    }
    expect(retried, isTrue);
    expect(discarded, isTrue);
    expect(kept, isTrue);
  });
}

CharacterImageModel _image(String path, String generation) =>
    CharacterImageModel(
      jobId: 'job-$generation',
      path: path,
      generation: generation,
      contentType: 'image/png',
      url: '',
      selected: generation == '1',
      createdAt: null,
    );
