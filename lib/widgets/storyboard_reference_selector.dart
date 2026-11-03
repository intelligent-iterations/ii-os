import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import 'character_image_preview.dart';

const storyboardReferenceLimit = 3;

final class StoryboardPanelReferenceOption {
  const StoryboardPanelReferenceOption({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnail,
  });

  final String id;
  final String name;
  final String description;
  final Widget thumbnail;
}

class StoryboardReferenceSelector extends StatelessWidget {
  const StoryboardReferenceSelector({
    required this.characters,
    this.controller,
    required this.panels,
    required this.selectedCharacterIds,
    required this.selectedPanelIds,
    required this.loadingCharacters,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final List<CharacterModel> characters;
  final AppController? controller;
  final List<StoryboardPanelReferenceOption> panels;
  final Set<String> selectedCharacterIds;
  final Set<String> selectedPanelIds;
  final bool loadingCharacters;
  final bool enabled;
  final VoidCallback onChanged;

  int get _selectedCount =>
      selectedCharacterIds.length + selectedPanelIds.length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reference images',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '$_selectedCount/$storyboardReferenceLimit selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Choose up to 3 total characters or panels. Their selected images are sent together to Qwen Image Edit.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Text('Characters', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        if (loadingCharacters)
          const Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Loading characters'),
            ],
          )
        else if (characters.isEmpty)
          Text(
            'No characters with a selected sheet are available.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final character in characters) _characterChip(character),
            ],
          ),
        IiOsGap.vSm,
        Text('Panels', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        if (panels.isEmpty)
          Text(
            'Generate a panel image to use it as a reference.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final panel in panels) _panelChip(panel)],
          ),
      ],
    );
  }

  Widget _characterChip(CharacterModel character) {
    final selected = selectedCharacterIds.contains(character.id);
    return FilterChip(
      key: ValueKey('storyboard-character-reference-${character.id}'),
      label: Text(character.name),
      selected: selected,
      avatar: controller == null || character.thumbnailImage == null
          ? const Icon(LucideIcons.scanFace, size: 16)
          : ClipOval(
              child: SizedBox.square(
                dimension: 24,
                child: CharacterVerifiedImage(
                  controller: controller!,
                  image: character.thumbnailImage!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
      onSelected: _canChange(selected)
          ? (value) {
              if (value) {
                selectedCharacterIds.add(character.id);
              } else {
                selectedCharacterIds.remove(character.id);
              }
              onChanged();
            }
          : null,
    );
  }

  Widget _panelChip(StoryboardPanelReferenceOption panel) {
    final selected = selectedPanelIds.contains(panel.id);
    return Tooltip(
      message: panel.description,
      child: FilterChip(
        key: ValueKey('storyboard-panel-reference-${panel.id}'),
        label: Text(panel.name),
        selected: selected,
        avatar: panel.thumbnail,
        onSelected: _canChange(selected)
            ? (value) {
                if (value) {
                  selectedPanelIds.add(panel.id);
                } else {
                  selectedPanelIds.remove(panel.id);
                }
                onChanged();
              }
            : null,
      ),
    );
  }

  bool _canChange(bool selected) =>
      enabled && (selected || _selectedCount < storyboardReferenceLimit);
}
