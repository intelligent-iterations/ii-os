import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'character_image_preview.dart';

class CharacterHistoricalPicker extends StatelessWidget {
  const CharacterHistoricalPicker({
    required this.bodyImages,
    this.controller,
    required this.bodyLoading,
    this.pendingJobId,
    required this.canSelect,
    required this.selectingPath,
    required this.onSelect,
    required this.onRefresh,
    required this.onDelete,
    super.key,
  });

  final List<CharacterImageModel> bodyImages;
  final AppController? controller;
  final bool bodyLoading;
  final String? pendingJobId;
  final bool canSelect;
  final String? selectingPath;
  final ValueChanged<CharacterImageModel> onSelect;
  final VoidCallback onRefresh;
  final ValueChanged<CharacterImageModel> onDelete;

  @override
  Widget build(BuildContext context) {
    if (bodyLoading && bodyImages.isEmpty && pendingJobId == null) {
      return const SizedBox.square(
        dimension: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final referenceCount = bodyImages.length + (pendingJobId == null ? 0 : 1);
    return SizedBox(
      key: const ValueKey('character-history-thumbnails'),
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: referenceCount + 1,
        separatorBuilder: (_, _) => IiOsGap.hXs,
        itemBuilder: (context, index) {
          if (index == referenceCount) {
            return _RefreshTile(enabled: !bodyLoading, onRefresh: onRefresh);
          }
          if (pendingJobId != null && index == 0) {
            return _PendingReferenceCard(jobId: pendingJobId!);
          }
          final image = bodyImages[index - (pendingJobId == null ? 0 : 1)];
          return _ReferenceTile(
            image: image,
            controller: controller,
            canSelect: canSelect,
            selectingPath: selectingPath,
            onSelect: onSelect,
            onDelete: onDelete,
          );
        },
      ),
    );
  }
}

class _RefreshTile extends StatelessWidget {
  const _RefreshTile({required this.enabled, required this.onRefresh});

  final bool enabled;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 64,
    child: OutlinedButton(
      key: const ValueKey('character-history-refresh'),
      onPressed: enabled ? onRefresh : null,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IiOsRadii.md),
        ),
      ),
      child: enabled
          ? const Tooltip(
              message: 'Refresh character sheets',
              child: Icon(LucideIcons.refreshCw, size: 17),
            )
          : const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    ),
  );
}

class _ReferenceTile extends StatelessWidget {
  const _ReferenceTile({
    required this.image,
    required this.controller,
    required this.canSelect,
    required this.selectingPath,
    required this.onSelect,
    required this.onDelete,
  });

  final CharacterImageModel image;
  final AppController? controller;
  final bool canSelect;
  final String? selectingPath;
  final ValueChanged<CharacterImageModel> onSelect;
  final ValueChanged<CharacterImageModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final selected = image.selected;
    return Tooltip(
      message: image.editLabel ?? image.filename,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Select ${image.filename} as the character sheet',
        child: Material(
          key: ValueKey('character-history-character sheet-${image.path}'),
          color: IiOsColors.canvas,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? IiOsColors.green : IiOsColors.border,
              width: selected ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(IiOsRadii.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: !canSelect || selected
                ? controller == null
                      ? null
                      : () => showCharacterImagePreview(
                          context,
                          controller!,
                          image,
                        )
                : selectingPath == null
                ? () => onSelect(image)
                : null,
            child: SizedBox.square(
              dimension: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  controller == null
                      ? const Icon(
                          LucideIcons.imageOff,
                          color: IiOsColors.muted,
                        )
                      : CharacterVerifiedImage(
                          controller: controller!,
                          image: image,
                          fit: BoxFit.cover,
                        ),
                  if (canSelect && !image.isSourceImage)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: IiOsColors.ink.withValues(alpha: .72),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: 24,
                          child: IconButton(
                            tooltip: 'Delete historical sheet',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              LucideIcons.trash2,
                              size: 13,
                              color: Colors.white,
                            ),
                            onPressed: () => onDelete(image),
                          ),
                        ),
                      ),
                    ),
                  if (image.isSourceImage || image.editLabel != null)
                    Positioned(
                      left: 3,
                      bottom: 3,
                      right: image.editLabel == null ? null : 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: IiOsColors.ink.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(IiOsRadii.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            image.isSourceImage
                                ? 'Original'
                                : image.editLabel!.split(':').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingReferenceCard extends StatelessWidget {
  const _PendingReferenceCard({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'A new character sheet is being generated.',
    child: Container(
      key: ValueKey('character-history-pending-$jobId'),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: IiOsColors.canvas,
        border: Border.all(color: IiOsColors.green, width: 2),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}
