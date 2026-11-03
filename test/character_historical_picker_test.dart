import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/widgets/character_historical_picker.dart';

void main() {
  testWidgets('renders an edited sheet as a separate loading thumbnail', (
    tester,
  ) async {
    const image = CharacterImageModel(
      jobId: 'old-job',
      path: 'old.png',
      generation: '1',
      contentType: 'image/png',
      url: '',
      selected: true,
      createdAt: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterHistoricalPicker(
            bodyImages: const [image],
            bodyLoading: false,
            pendingJobId: 'edit-job',
            canSelect: true,
            selectingPath: null,
            onSelect: (_) {},
            onRefresh: () {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('character-history-pending-edit-job')),
      findsOneWidget,
    );
    expect(find.text('Creating new sheet'), findsNothing);
    expect(find.text('Historical references'), findsNothing);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('character-history-pending-edit-job')),
      ),
      const Size.square(64),
    );
    expect(
      find.byKey(const ValueKey('character-history-character sheet-old.png')),
      findsOneWidget,
    );
  });

  testWidgets('delivers a loaded preview selection on the tap frame', (
    tester,
  ) async {
    const selected = CharacterImageModel(
      jobId: 'old-job',
      path: 'old.png',
      generation: '1',
      contentType: 'image/png',
      url: '',
      selected: true,
      createdAt: null,
    );
    const next = CharacterImageModel(
      jobId: 'next-job',
      path: 'next.png',
      generation: '2',
      contentType: 'image/png',
      url: '',
      selected: false,
      createdAt: null,
    );
    CharacterImageModel? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterHistoricalPicker(
            bodyImages: const [selected, next],
            bodyLoading: false,
            canSelect: true,
            selectingPath: null,
            onSelect: (image) => tapped = image,
            onRefresh: () {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('character-history-character sheet-next.png')),
    );

    expect(tapped, same(next));
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('character-history-character sheet-next.png'),
        ),
      ),
      const Size.square(64),
    );
    expect(
      find.byKey(const ValueKey('character-image-preview-dialog')),
      findsNothing,
    );
  });

  testWidgets('shows the original prompt image as selectable and protected', (
    tester,
  ) async {
    const source = CharacterImageModel(
      jobId: 'source-asset:source-1',
      path: 'source/reference.png',
      generation: '7',
      contentType: 'image/png',
      url: '',
      isSourceImage: true,
      selected: false,
      createdAt: null,
    );
    CharacterImageModel? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterHistoricalPicker(
            bodyImages: const [source],
            bodyLoading: false,
            canSelect: true,
            selectingPath: null,
            onSelect: (image) => tapped = image,
            onRefresh: () {},
            onDelete: (_) =>
                fail('The original source image is not deletable.'),
          ),
        ),
      ),
    );

    expect(find.text('Original'), findsOneWidget);
    expect(find.byTooltip('Delete historical sheet'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'character-history-character sheet-source/reference.png',
        ),
      ),
    );

    expect(tapped, same(source));
  });

  testWidgets('shows a concise label for an accepted edit version', (
    tester,
  ) async {
    const edited = CharacterImageModel(
      jobId: 'edit-job',
      path: 'edited.png',
      generation: '8',
      contentType: 'image/png',
      url: '',
      editLabel: 'Area edit: Smaller chest marking',
      selected: true,
      createdAt: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterHistoricalPicker(
            bodyImages: const [edited],
            bodyLoading: false,
            canSelect: true,
            selectingPath: null,
            onSelect: (_) {},
            onRefresh: () {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Area edit'), findsOneWidget);
    expect(find.byTooltip('Area edit: Smaller chest marking'), findsOneWidget);
  });
}
