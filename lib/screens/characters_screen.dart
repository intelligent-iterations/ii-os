import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/character.dart';
import '../repositories/character_repository.dart';
import '../state/app_controller.dart';
import '../view_models/characters_view_model.dart';
import '../widgets/common.dart';
import 'character_builder_screen.dart';
import 'character_detail_screen.dart';
import 'characters_grid.dart';

/// The characters collection. Layout only -- the list, the in-flight create, and
/// the sheet jobs live in [CharactersViewModel].
class CharactersScreen extends StatelessWidget {
  const CharactersScreen({
    required this.controller,
    this.selectedCharacterId,
    this.onSelectCharacter,
    this.onCloseCharacter,
    this.repository,
    super.key,
  });

  final AppController controller;
  final String? selectedCharacterId;
  final ValueChanged<String>? onSelectCharacter;
  final VoidCallback? onCloseCharacter;

  /// Injectable so a test can count fetches. Defaults to the API-backed
  /// repository, matching how the other API-backed screens take theirs.
  final CharacterRepository? repository;

  bool get _canWrite => controller.can('characters.write');

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<CharactersViewModel>.reactive(
      viewModelBuilder: () => CharactersViewModel(
        characters: repository ?? CharacterApiRepository(controller.api),
        workspaceId: controller.workspace!.id,
      ),
      onViewModelReady: (model) => model.load(
        selectedCharacterId: selectedCharacterId,
        onSelectionMissing: onCloseCharacter,
      ),
      builder: (context, model, _) {
        final selected = model.selected(selectedCharacterId);
        if (selected != null) {
          return _CharacterDetailRoute(
            model: model,
            controller: controller,
            character: selected,
            canWrite: _canWrite,
            onClose: () => _close(model),
            onDeleted: () {
              model.remove(selected.id);
              onCloseCharacter?.call();
            },
          );
        }
        return PageFrame(
          title: 'Characters',
          subtitle: 'Character sheets and saved Z-Image prompts',
          actions: [
            OutlinedButton.icon(
              onPressed: model.isBusy ? null : () => _reload(model),
              icon: const Icon(LucideIcons.refreshCw, size: IiOsIconSize.md),
              label: const Text('Refresh'),
            ),
          ],
          child: CharactersGrid(
            model: model,
            controller: controller,
            canWrite: _canWrite,
            onSelectCharacter: onSelectCharacter,
          ),
        );
      },
    );
  }

  void _close(CharactersViewModel model) {
    model.clearGenerations();
    onCloseCharacter?.call();
    _reload(model);
  }

  void _reload(CharactersViewModel model) => model.load(
    selectedCharacterId: selectedCharacterId,
    onSelectionMissing: onCloseCharacter,
  );
}

/// The open character: the guided builder while it is still a scratch sheet,
/// the detail screen once it is a real one.
///
/// Both are full-page takeovers rather than children of the grid, which is why
/// the page returns this instead of composing it into [PageFrame].
class _CharacterDetailRoute extends StatelessWidget {
  const _CharacterDetailRoute({
    required this.model,
    required this.controller,
    required this.character,
    required this.canWrite,
    required this.onClose,
    required this.onDeleted,
  });

  final CharactersViewModel model;
  final AppController controller;
  final CharacterModel character;
  final bool canWrite;
  final VoidCallback onClose;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    if (character.opensScratchBuilder && canWrite) {
      return CharacterBuilderScreen(
        controller: controller,
        character: character,
        onSaved: model.replace,
        onGenerated: model.recordGeneration,
        onClose: onClose,
      );
    }
    return CharacterDetailScreen(
      controller: controller,
      character: character,
      canWrite: canWrite,
      initialGeneration: model.generationResult,
      initialBodyGeneration: model.bodyGenerationResult,
      onSaved: model.replace,
      onDeleted: onDeleted,
      onClose: onClose,
    );
  }
}
