import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/character_repository.dart';
import 'package:ii_os/screens/characters_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

/// Counts how many times the screen actually goes to the control API.
///
/// Only [list] is exercised here; the mutations are covered by
/// `characters_view_model_test.dart`, and failing loudly is better than
/// silently returning a stub if this test ever starts triggering one.
final class _CountingCharacters implements CharacterRepository {
  _CountingCharacters(this.characters);

  final List<CharacterModel> characters;
  int calls = 0;

  @override
  Future<List<CharacterModel>> list(String workspaceId) async {
    calls++;
    return characters;
  }

  @override
  Future<CharacterModel> create(String workspaceId) =>
      throw UnimplementedError();

  @override
  Future<CharacterModel> createFromImage({
    required String workspaceId,
    required String name,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String bucket,
  }) => throw UnimplementedError();

  @override
  Future<CharacterGeneration> generateFromImage(
    String workspaceId,
    String characterId,
  ) => throw UnimplementedError();

  @override
  Future<void> delete(String workspaceId, String characterId) =>
      throw UnimplementedError();
}

CharacterModel _character(String id) => CharacterModel.fromJson({
  'id': id,
  'name': id,
  'status': 'ready',
});

AppController _controller() => AppController()
  ..selectedAccess = const WorkspaceAccess(
    workspace: WorkspaceModel(
      id: 'ws_test',
      name: 'Test workspace',
      environment: 'dev',
      githubInstallationId: 12,
      repositories: ['acme/media'],
      projects: [],
      workflows: ['image-create'],
      artifactStorage: null,
    ),
    membership: MembershipModel(
      workspaceId: 'ws_test',
      uid: 'owner-1',
      email: 'owner@example.com',
      role: 'owner',
      roleLabel: 'Owner',
      featureClaims: {},
      capabilities: {'characters.read'},
    ),
  );

void main() {
  /// The page key the operator shell gives every routed page. Before the fix
  /// it also carried the selected item id, so every selection produced a
  /// different widget identity, Flutter tore the page's State down, and
  /// `initState` refetched the whole collection.
  const shellPageKey = ValueKey('ws_test:characters');

  Widget harness({
    required AppController controller,
    required CharacterRepository repository,
    required Key key,
    String? selectedCharacterId,
  }) {
    return MaterialApp(
      theme: IiOsTheme.light(),
      home: CharactersScreen(
        key: key,
        controller: controller,
        repository: repository,
        selectedCharacterId: selectedCharacterId,
      ),
    );
  }

  testWidgets('selecting an item does not refetch the collection', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final repository = _CountingCharacters([_character('c1'), _character('c2')]);

    await tester.pumpWidget(
      harness(
        controller: controller,
        repository: repository,
        key: shellPageKey,
      ),
    );
    await tester.pump();
    expect(repository.calls, 1, reason: 'the first mount loads once');

    // Selection changes exactly as the shell drives it: same page key, new
    // itemId. The State must survive, so no second fetch.
    await tester.pumpWidget(
      harness(
        controller: controller,
        repository: repository,
        key: shellPageKey,
        selectedCharacterId: 'c1',
      ),
    );
    await tester.pump();
    expect(repository.calls, 1, reason: 'opening a character must not refetch');

    await tester.pumpWidget(
      harness(
        controller: controller,
        repository: repository,
        key: shellPageKey,
        selectedCharacterId: 'c2',
      ),
    );
    await tester.pump();
    expect(
      repository.calls,
      1,
      reason: 'moving between characters must not refetch',
    );

    await tester.pumpWidget(
      harness(
        controller: controller,
        repository: repository,
        key: shellPageKey,
      ),
    );
    await tester.pump();
    expect(
      repository.calls,
      1,
      reason: 'returning to the list by route alone must not refetch',
    );
  });

  testWidgets('negative control: a new page key does refetch', (tester) async {
    // Proves the counter above can actually observe a refetch. If this test
    // fails, the first one is passing vacuously.
    final controller = _controller();
    addTearDown(controller.dispose);
    final repository = _CountingCharacters([_character('c1')]);

    await tester.pumpWidget(
      harness(
        controller: controller,
        repository: repository,
        key: shellPageKey,
      ),
    );
    await tester.pump();
    expect(repository.calls, 1);

    // What a workspace switch looks like: a different page key.
    await tester.pumpWidget(
      harness(
        controller: controller,
        repository: repository,
        key: const ValueKey('ws_other:characters'),
      ),
    );
    await tester.pump();
    expect(
      repository.calls,
      2,
      reason: 'a genuinely new page must load its own data',
    );
  });

  testWidgets('the pre-fix key shape refetches on every selection', (
    tester,
  ) async {
    // Reproduces the defect this change removed: when the item id is part of
    // the key, each selection is a new widget identity and reloads everything.
    final controller = _controller();
    addTearDown(controller.dispose);
    final repository = _CountingCharacters([_character('c1'), _character('c2')]);

    for (final itemId in [null, 'c1', 'c2']) {
      await tester.pumpWidget(
        harness(
          controller: controller,
          repository: repository,
          key: ValueKey('ws_test:characters:${itemId ?? ''}'),
          selectedCharacterId: itemId,
        ),
      );
      await tester.pump();
    }

    expect(
      repository.calls,
      3,
      reason: 'the old key shape cost one full round-trip per selection',
    );
  });

  test('parseCharacters tolerates an absent collection', () {
    expect(parseCharacters(const {}), isEmpty);
    expect(parseCharacters(const {'characters': 'nope'}), isEmpty);
    expect(
      parseCharacters(const {
        'characters': [
          {'id': 'c1', 'name': 'One', 'status': 'ready'},
        ],
      }).single.id,
      'c1',
    );
  });
}
