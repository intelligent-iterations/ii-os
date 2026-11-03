import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/generation_history.dart';
import 'artifact_thumbnail.dart';

/// One asset in a library grid.
///
/// Reads as a picture first: the prompt sits over the artwork rather than in a
/// caption underneath, so a tile stays a tile at any column count, and the
/// kind badge says whether tapping it gets a still or something that moves.
class MediaLibraryTile extends StatelessWidget {
  const MediaLibraryTile({
    required this.entry,
    required this.loadPreview,
    required this.onPick,
    super.key,
    this.selected,
  });

  final HistoryEntryModel entry;

  /// `null` when this entry has no preview to render -- audio, or a video
  /// generated before posters existed.
  final ArtifactPreviewLoader? loadPreview;
  final ValueChanged<HistoryEntryModel> onPick;

  /// `null` in a single-select grid, where choosing is the same act as
  /// closing and there is no state worth drawing.
  final bool? selected;

  bool get _isVideo => entry.contentType.startsWith('video/');

  String get _label {
    final prompt = entry.generation.prompt.trim();
    return prompt.isEmpty ? entry.filename : prompt;
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Semantics(
      button: true,
      label:
          '${_isVideo
              ? 'Video'
              : entry.isAudio
              ? 'Audio'
              : 'Image'}, '
          '$_label',
      child: ExcludeSemantics(
        child: Material(
          color: palette.mediaWell,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: IiOsRadii.lgAll,
            side: BorderSide(
              color: selected ?? false ? palette.brand.text : palette.border,
              width: selected ?? false ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => onPick(entry),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArtifactThumbnail(
                  identity: entry.identity,
                  load: loadPreview,
                  errorSource: 'library.picker.thumbnail',
                  placeholderIcon: entry.isAudio
                      ? LucideIcons.audioLines
                      : LucideIcons.play,
                ),
                const _Scrim(),
                Positioned(
                  left: IiOsSpacing.xs,
                  right: IiOsSpacing.xs,
                  bottom: IiOsSpacing.xs,
                  child: Text(
                    _label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                ),
                if (_isVideo || entry.isAudio)
                  Positioned(
                    top: IiOsSpacing.xs,
                    right: IiOsSpacing.xs,
                    child: _KindBadge(
                      icon: _isVideo
                          ? LucideIcons.play
                          : LucideIcons.audioLines,
                    ),
                  ),
                if (selected ?? false)
                  Positioned(
                    top: IiOsSpacing.xs,
                    right: IiOsSpacing.xs,
                    child: IiOsChosenTick(color: palette.brand.text),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the caption legible over artwork of any brightness.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.center,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xCC0A0C10)],
      ),
    ),
  );
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0x99101318),
      shape: BoxShape.circle,
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.xxs),
      child: Icon(icon, size: IiOsIconSize.sm, color: Colors.white),
    ),
  );
}
