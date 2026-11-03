import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/storyboard_reference_selector.dart';

void main() {
  testWidgets('characters and panels share a mobile-safe limit of three', (
    tester,
  ) async {
    final selectedCharacters = <String>{'character-1', 'character-2'};
    final selectedPanels = <String>{};
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => StoryboardReferenceSelector(
                characters: [
                  _character('character-1', 'Mara'),
                  _character('character-2', 'Jules'),
                  _character('character-3', 'Nia'),
                ],
                panels: const [
                  StoryboardPanelReferenceOption(
                    id: 'panel-1',
                    name: 'Panel 1',
                    description: 'Mara reaches the station.',
                    thumbnail: SizedBox.square(
                      key: ValueKey('panel-1-thumbnail'),
                      dimension: 22,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                  StoryboardPanelReferenceOption(
                    id: 'panel-2',
                    name: 'Panel 2',
                    description: 'The train pulls away.',
                    thumbnail: SizedBox.square(
                      key: ValueKey('panel-2-thumbnail'),
                      dimension: 22,
                      child: ColoredBox(color: Colors.green),
                    ),
                  ),
                ],
                selectedCharacterIds: selectedCharacters,
                selectedPanelIds: selectedPanels,
                loadingCharacters: false,
                enabled: true,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('2/3 selected'), findsOneWidget);
    expect(find.text('Panel 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-1-thumbnail')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('storyboard-panel-reference-panel-1')),
    );
    await tester.pump();

    expect(selectedPanels, {'panel-1'});
    expect(find.text('3/3 selected'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(
              const ValueKey('storyboard-character-reference-character-3'),
            ),
          )
          .onSelected,
      isNull,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('storyboard-panel-reference-panel-2')),
          )
          .onSelected,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('storyboard-character-reference-character-1')),
    );
    await tester.pump();

    expect(selectedCharacters, {'character-2'});
    expect(find.text('2/3 selected'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('storyboard-panel-reference-panel-2')),
          )
          .onSelected,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}

CharacterModel _character(String id, String name) => CharacterModel(
  id: id,
  workspaceId: 'workspace-1',
  name: name,
  answers: const {},
  prompt: '$name reference',
  status: 'ready',
  thumbnailUrl: null,
  selectedImage: CharacterImageReference(
    jobId: '$id-job',
    path: '$id.png',
    generation: '1',
    contentType: 'image/png',
  ),
  createdAt: null,
  updatedAt: null,
);
