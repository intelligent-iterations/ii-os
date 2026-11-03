import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'character_image_preview.dart';
import 'common.dart';

class CharacterImageGallery extends StatefulWidget {
  const CharacterImageGallery({
    this.title = 'Generated character images',
    this.selectionDescription,
    required this.images,
    required this.controller,
    required this.loading,
    this.loadError,
    required this.canSelect,
    required this.selectingPath,
    required this.onSelect,
    required this.onRefresh,
    super.key,
  });

  final String title;
  final String? selectionDescription;
  final List<CharacterImageModel> images;
  final AppController controller;
  final bool loading;
  final String? loadError;
  final bool canSelect;
  final String? selectingPath;
  final ValueChanged<CharacterImageModel> onSelect;
  final VoidCallback onRefresh;

  @override
  State<CharacterImageGallery> createState() => _CharacterImageGalleryState();
}

class _CharacterImageGalleryState extends State<CharacterImageGallery> {
  String? _previewPath;

  @override
  void didUpdateWidget(covariant CharacterImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previewPath != null &&
        !widget.images.any((image) => image.path == _previewPath)) {
      _previewPath = null;
    }
  }

  CharacterImageModel? get _preview {
    for (final image in widget.images) {
      if (image.path == _previewPath) return image;
    }
    for (final image in widget.images) {
      if (image.selected) return image;
    }
    return widget.images.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              widget.title,
              trailing: IconButton(
                tooltip: 'Refresh generated images',
                onPressed: widget.loading ? null : widget.onRefresh,
                icon: widget.loading
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 17),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              widget.selectionDescription ??
                  'Choose a historical result below to see it large, then make it the selected reference.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vMd,
            if (widget.loadError != null) ...[
              _GalleryError(
                message: widget.loadError!,
                onRetry: widget.onRefresh,
              ),
              IiOsGap.vMd,
            ],
            if (_assetErrorMessage != null) ...[
              _GalleryError(
                message: _assetErrorMessage!,
                onRetry: widget.onRefresh,
              ),
              IiOsGap.vMd,
            ],
            if (widget.loading && widget.images.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (preview == null)
              const _EmptyGallery()
            else ...[
              _LargePreview(
                image: preview,
                controller: widget.controller,
                selecting: widget.selectingPath == preview.path,
                canSelect:
                    widget.canSelect &&
                    widget.selectingPath == null &&
                    !preview.selected,
                onExpand: () => showCharacterImagePreview(
                  context,
                  widget.controller,
                  preview,
                ),
                onSelect: () => widget.onSelect(preview),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  key: const ValueKey('character-image-history'),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final image = widget.images[index];
                    return _HistoryThumbnail(
                      image: image,
                      controller: widget.controller,
                      previewed: image.path == preview.path,
                      onTap: () => setState(() => _previewPath = image.path),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _assetErrorMessage {
    for (final image in widget.images) {
      final message = image.urlErrorMessage?.trim() ?? '';
      if (message.isNotEmpty) return message;
    }
    return null;
  }
}

class _LargePreview extends StatelessWidget {
  const _LargePreview({
    required this.image,
    required this.controller,
    required this.selecting,
    required this.canSelect,
    required this.onExpand,
    required this.onSelect,
  });

  final CharacterImageModel image;
  final AppController controller;
  final bool selecting;
  final bool canSelect;
  final VoidCallback onExpand;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            key: ValueKey('character-image-large-${image.path}'),
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onExpand,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CharacterVerifiedImage(controller: controller, image: image),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _Badge(
                      icon: LucideIcons.expand,
                      label: 'View full size',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                image.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (image.selected)
              const _Badge(icon: LucideIcons.check, label: 'Selected')
            else if (selecting)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (canSelect)
              FilledButton.tonalIcon(
                key: ValueKey('select-character-image-${image.path}'),
                onPressed: onSelect,
                icon: const Icon(LucideIcons.check, size: 15),
                label: const Text('Use this image'),
              ),
          ],
        ),
      ],
    );
  }
}

class _HistoryThumbnail extends StatelessWidget {
  const _HistoryThumbnail({
    required this.image,
    required this.controller,
    required this.previewed,
    required this.onTap,
  });

  final CharacterImageModel image;
  final AppController controller;
  final bool previewed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = image.selected
        ? IiOsColors.green
        : previewed
        ? IiOsColors.blue
        : IiOsColors.border;
    return Semantics(
      button: true,
      selected: previewed,
      label: 'Preview ${image.filename}',
      child: Material(
        key: ValueKey('character-image-${image.path}'),
        color: IiOsColors.canvas,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: borderColor,
            width: image.selected || previewed ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(IiOsRadii.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 108,
            child: CharacterVerifiedImage(
              controller: controller,
              image: image,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(IiOsRadii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: IiOsColors.green),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        Icon(LucideIcons.images, size: 30, color: IiOsColors.muted),
        IiOsGap.vXs,
        Text(
          'Generated images will appear here without replacing earlier results.',
          textAlign: TextAlign.center,
          style: TextStyle(color: IiOsColors.muted),
        ),
      ],
    ),
  );
}

class _GalleryError extends StatelessWidget {
  const _GalleryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.amberTint,
      border: Border.all(color: IiOsColors.amber),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Row(
        children: [
          const Icon(LucideIcons.triangleAlert, color: IiOsColors.amber),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
