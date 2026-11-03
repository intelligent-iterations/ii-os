import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../services/source_asset_uploader.dart';
import '../state/app_controller.dart';
import '../view_models/characters_view_model.dart';
import '../widgets/character_image_preview.dart';
import '../widgets/common.dart';
import 'character_media_picker.dart';
import 'characters_screen_dialogs.dart';

/// The characters collection body: first load, failure, empty state, or grid.
///
/// Split from the page so `characters_screen.dart` stays a description of the
/// page rather than a description of a card.
class CharactersGrid extends StatelessWidget {
  const CharactersGrid({
    required this.model,
    required this.controller,
    required this.canWrite,
    required this.onSelectCharacter,
    super.key,
  });

  final CharactersViewModel model;
  final AppController controller;
  final bool canWrite;
  final ValueChanged<String>? onSelectCharacter;

  @override
  Widget build(BuildContext context) {
    if (model.showLoadingSurface) {
      return const LoadingSurface(label: 'Loading characters');
    }
    final error = model.errorMessage;
    if (error != null) {
      return ErrorSurface(
        title: 'Characters could not be loaded',
        message: error,
        onRetry: () => model.load(),
      );
    }
    final itemCount = model.characters.length + (canWrite ? 1 : 0);
    if (itemCount == 0) {
      return const Card(
        child: EmptyState(
          title: 'No characters yet',
          message: 'Characters created for this workspace will appear here.',
          icon: LucideIcons.scanFace,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: math.max(
            1,
            (constraints.maxWidth / _cardTargetWidth).floor(),
          ),
          crossAxisSpacing: IiOsSpacing.md,
          mainAxisSpacing: IiOsSpacing.md,
          childAspectRatio: _cardAspectRatio,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (canWrite && index == 0) {
            return _NewCharacterCard(
              model: model,
              controller: controller,
              onCreated: onSelectCharacter,
            );
          }
          return _CharacterCard(
            model: model,
            controller: controller,
            character: model.characters[index - (canWrite ? 1 : 0)],
            canWrite: canWrite,
            onSelectCharacter: onSelectCharacter,
          );
        },
      ),
    );
  }

  /// How wide a card wants to be before the grid adds another column. Not a
  /// breakpoint: this asks how many cards fit, not how wide the window is.
  static const _cardTargetWidth = 220.0;

  /// Slightly taller than square, which is what a portrait thumbnail plus two
  /// lines of caption needs.
  static const _cardAspectRatio = 0.83;
}

/// The create affordance, sitting in the grid as the first card.
class _NewCharacterCard extends StatelessWidget {
  const _NewCharacterCard({
    required this.model,
    required this.controller,
    required this.onCreated,
  });

  final CharactersViewModel model;
  final AppController controller;

  final ValueChanged<String>? onCreated;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: model.creating ? null : () => _create(context),
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CreateGlyph(pending: model.creating),
              IiOsGap.vSm,
              Text(
                'New character',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IiOsGap.vXxs,
              Text(
                'Build head and body reference sheets',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final mode = await askCreateMode(context);
    if (mode == null || !context.mounted) return;
    final outcome = mode == 'image'
        ? await _fromImage(context)
        : await model.createScratch();
    if (outcome == null || !context.mounted) return;
    final failure = outcome.failure;
    if (failure != null) showFailure(context, failure);
    // Opened even when the sheet failed to start: the character exists, and
    // the detail screen is where the operator retries it.
    final created = outcome.character;
    if (created != null) onCreated?.call(created.id);
  }

  /// Null when the operator backed out. A dismissed name prompt or file picker
  /// is not a failure, so it must not reach [showFailure].
  Future<CreateOutcome?> _fromImage(BuildContext context) async {
    final name = await askCharacterName(context);
    if (name == null || !context.mounted) return null;
    final selected = await pickCharacterImage(
      context,
      controller: controller,
      maxBytes: _maxCharacterImageBytes,
    );
    if (selected == null || !context.mounted) return null;
    final file = selected.file;
    final bytes = selected.bytes;
    final contentType = sourceImageContentType(bytes);
    if (bytes.length > _maxCharacterImageBytes || contentType == null) {
      return const CreateOutcome(
        failure: FormatException(
          'Choose a PNG, JPEG, or WebP image under 50 MB.',
        ),
      );
    }
    return model.createFromImage(
      name: name,
      filename: file.name,
      bytes: bytes,
      contentType: contentType,
      bucket: controller.connection?.bucket ?? '',
    );
  }
}

const _maxCharacterImageBytes = 50 * 1024 * 1024;

/// The tinted circle on the create card, showing progress in place.
class _CreateGlyph extends StatelessWidget {
  const _CreateGlyph({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        color: IiOsColors.green.withValues(alpha: _tintAlpha),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: PendingIcon(
          icon: LucideIcons.plus,
          pending: pending,
          size: IiOsIconSize.xl,
          color: IiOsColors.green,
          pendingLabel: 'Creating character',
        ),
      ),
    );
  }

  static const _diameter = 54.0;

  /// A wash, not a fill: the glyph inside has to stay the readable element.
  static const _tintAlpha = 0.09;
}

/// One character in the grid.
class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.model,
    required this.controller,
    required this.character,
    required this.canWrite,
    required this.onSelectCharacter,
  });

  final CharactersViewModel model;
  final AppController controller;
  final CharacterModel character;
  final bool canWrite;
  final ValueChanged<String>? onSelectCharacter;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          model.clearGenerations();
          onSelectCharacter?.call(character.id);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _GridThumbnail(controller: controller, character: character),
                  if (canWrite)
                    Positioned(
                      right: IiOsSpacing.xxs,
                      top: IiOsSpacing.xxs,
                      child: _CardMenu(model: model, character: character),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(IiOsSpacing.sm),
              child: _CardCaption(character: character),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name, status, and questionnaire progress under the thumbnail.
class _CardCaption extends StatelessWidget {
  const _CardCaption({required this.character});

  final CharacterModel character;

  @override
  Widget build(BuildContext context) {
    final status = character.presentationStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          character.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IiOsGap.vXxs,
        Row(
          children: [
            StatusPill(status, color: _statusColor(status)),
            const Spacer(),
            if (character.opensScratchBuilder)
              Text(
                '${character.answeredQuestions}/${characterQuestions.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }

  static Color _statusColor(String status) => switch (status) {
    'ready' => IiOsColors.green,
    'failed' => IiOsColors.red,
    'cancelled' => IiOsColors.muted,
    'generating' => IiOsColors.blue,
    _ => IiOsColors.amber,
  };
}

/// The per-card overflow menu. On its own opaque disc so it stays legible over
/// whatever the thumbnail happens to be.
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.model, required this.character});

  final CharactersViewModel model;
  final CharacterModel character;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: IiOsColors.surface,
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Character actions',
        icon: const Icon(LucideIcons.ellipsis, size: IiOsIconSize.sm),
        onSelected: (value) {
          if (value == 'delete') _confirmDelete(context);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await confirmDeleteCharacter(context, character.name);
    if (!confirmed || !context.mounted) return;
    final failure = await model.deleteCharacter(character.id);
    if (failure != null && context.mounted) showFailure(context, failure);
  }
}

class _GridThumbnail extends StatelessWidget {
  const _GridThumbnail({required this.controller, required this.character});

  final AppController controller;
  final CharacterModel character;

  @override
  Widget build(BuildContext context) {
    final image = character.thumbnailImage;
    if (image != null) {
      return CharacterVerifiedImage(
        controller: controller,
        image: image,
        fit: BoxFit.cover,
      );
    }
    return const _GridPlaceholder();
  }
}

class _GridPlaceholder extends StatelessWidget {
  const _GridPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: IiOsColors.canvas,
      child: Center(
        child: Icon(
          LucideIcons.scanFace,
          size: IiOsIconSize.xxl,
          color: IiOsColors.muted,
        ),
      ),
    );
  }
}
