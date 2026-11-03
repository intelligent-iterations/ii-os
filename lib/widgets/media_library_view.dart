import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/generation_history.dart';
import '../services/verified_artifact_media.dart';
import 'media_library_tile.dart';

/// Loads the preview bytes for one library entry.
typedef LibraryPreviewLoader =
    Future<VerifiedArtifactMedia> Function(HistoryEntryModel entry);

/// The kinds a library grid can be narrowed to.
enum MediaKind {
  all('All', null),
  image('Images', 'image/'),
  video('Videos', 'video/'),
  audio('Audio', 'audio/');

  const MediaKind(this.label, this.prefix);

  final String label;
  final String? prefix;

  static MediaKind forPrefix(String? prefix) {
    for (final kind in values) {
      if (kind.prefix == prefix) return kind;
    }
    throw ArgumentError.value(prefix, 'prefix', 'Unsupported media kind');
  }

  bool includes(HistoryEntryModel entry) =>
      entry.isGeneratedMedia &&
      (prefix == null || entry.contentType.startsWith(prefix!));
}

class MediaLibraryKindSelector extends StatelessWidget {
  const MediaLibraryKindSelector({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final MediaKind selected;
  final ValueChanged<MediaKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: IiOsSpacing.lg,
        top: IiOsSpacing.sm,
        right: IiOsSpacing.lg,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<MediaKind>(
          showSelectedIcon: false,
          segments: [
            for (final option in MediaKind.values)
              ButtonSegment(value: option, label: Text(option.label)),
          ],
          selected: {selected},
          onSelectionChanged: (value) => onSelected(value.first),
        ),
      ),
    );
  }
}

/// Tile sizing. Wide enough that a prompt reads over the artwork, narrow
/// enough that a phone-width dialog still gets two columns.
const _tileExtent = 168.0;
const _tileAspect = 0.86;

class MediaLibraryView extends StatelessWidget {
  const MediaLibraryView({
    required this.entries,
    required this.controller,
    required this.loadPreview,
    required this.loadingMore,
    required this.onPick,
    super.key,
    this.chosen = const <String>{},
    this.multiple = false,
  });

  final List<HistoryEntryModel> entries;
  final ScrollController controller;
  final LibraryPreviewLoader loadPreview;
  final bool loadingMore;
  final ValueChanged<HistoryEntryModel> onPick;

  /// Identities already chosen, when the grid takes several.
  final Set<String> chosen;
  final bool multiple;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          // GridView.builder only builds the tiles in view, so a preview is
          // fetched when its tile is first reached rather than all at once.
          child: GridView.builder(
            controller: controller,
            padding: const EdgeInsets.only(bottom: IiOsSpacing.sm),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _tileExtent,
              crossAxisSpacing: IiOsSpacing.xs,
              mainAxisSpacing: IiOsSpacing.xs,
              childAspectRatio: _tileAspect,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return MediaLibraryTile(
                key: ValueKey(entry.identity),
                entry: entry,
                // No preview artifact means nothing to fetch; the tile shows
                // its kind rather than a spinner that never resolves.
                loadPreview: entry.previewArtifact == null
                    ? null
                    : () => loadPreview(entry),
                selected: multiple ? chosen.contains(entry.identity) : null,
                onPick: onPick,
              );
            },
          ),
        ),
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.only(bottom: IiOsSpacing.xs),
            child: SizedBox.square(
              dimension: IiOsIconSize.md,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}
