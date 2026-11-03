import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/generation_history.dart';
import '../repositories/generation_history_repository.dart';
import '../services/verified_artifact_media.dart';
import 'media_library_grid.dart';
import '../models/picked_media.dart';
import 'media_upload_pane.dart';

/// Loads the preview bytes for one library entry.
typedef HistoryPreviewLoader =
    Future<VerifiedArtifactMedia> Function(HistoryEntryModel entry);

/// Chooses one asset, from the workspace library or from the device.
///
/// Every media field in the product needs the same two answers. Before this
/// each one had grown half of it -- some could only upload, some could only
/// browse -- so which was possible depended on which screen you happened to be
/// on rather than on anything true about the task.
///
/// [loadPreview] is passed in rather than a controller, so the picker stays a
/// widget over data and callbacks.
/// Chooses several assets at once.
///
/// Returns null when the sheet was dismissed, and never an empty list: a
/// caller that has to tell "cancelled" from "chose nothing" gets it wrong.
Future<List<PickedMedia>?> showMediaPickerMultiple({
  required BuildContext context,
  required GenerationHistoryRepository history,
  required HistoryPreviewLoader loadPreview,
  String? contentTypePrefix,
  String title = 'Choose media',
  List<XTypeGroup> uploadTypes = const [],
  bool allowUpload = true,
  int? maxUploadBytes,
  int? maxTotalUploadBytes,
}) {
  return showDialog<List<PickedMedia>>(
    context: context,
    builder: (context) => _MediaPicker(
      history: history,
      loadPreview: loadPreview,
      contentTypePrefix: contentTypePrefix,
      title: title,
      uploadTypes: uploadTypes,
      allowUpload: allowUpload,
      maxUploadBytes: maxUploadBytes,
      maxTotalUploadBytes: maxTotalUploadBytes,
      multiple: true,
    ),
  );
}

Future<PickedMedia?> showMediaPicker({
  required BuildContext context,
  required GenerationHistoryRepository history,
  required HistoryPreviewLoader loadPreview,
  String? contentTypePrefix,
  String title = 'Choose media',
  List<XTypeGroup> uploadTypes = const [],
  bool allowUpload = true,
  int? maxUploadBytes,
}) {
  return showDialog<PickedMedia>(
    context: context,
    builder: (context) => _MediaPicker(
      history: history,
      loadPreview: loadPreview,
      contentTypePrefix: contentTypePrefix,
      title: title,
      uploadTypes: uploadTypes,
      allowUpload: allowUpload,
      maxUploadBytes: maxUploadBytes,
      maxTotalUploadBytes: maxUploadBytes,
      multiple: false,
    ),
  );
}

final class _MediaPicker extends StatefulWidget {
  const _MediaPicker({
    required this.history,
    required this.loadPreview,
    required this.contentTypePrefix,
    required this.title,
    required this.uploadTypes,
    required this.allowUpload,
    required this.maxUploadBytes,
    required this.maxTotalUploadBytes,
    required this.multiple,
  });

  final GenerationHistoryRepository history;
  final HistoryPreviewLoader loadPreview;
  final String? contentTypePrefix;
  final String title;
  final List<XTypeGroup> uploadTypes;
  final bool allowUpload;
  final int? maxUploadBytes;
  final int? maxTotalUploadBytes;
  final bool multiple;

  @override
  State<_MediaPicker> createState() => _MediaPickerState();
}

final class _MediaPickerState extends State<_MediaPicker> {
  MediaPickerSource _source = MediaPickerSource.library;

  /// Insertion-ordered, so what comes back matches the order they were chosen
  /// in rather than the order the grid happens to hold them.
  final Map<String, PickedMedia> _chosen = {};

  void _toggle(HistoryEntryModel entry) {
    setState(() {
      if (_chosen.remove(entry.identity) == null) {
        _chosen[entry.identity] = PickedMedia.fromLibrary(entry);
      }
    });
  }

  void _addUpload(PickedMedia picked) {
    if (!widget.multiple) {
      Navigator.of(context).pop(picked);
      return;
    }
    setState(() => _chosen[picked.upload!.path] = picked);
  }

  int get _chosenBytes => _chosen.values.fold<int>(
    0,
    (total, picked) =>
        total +
        (picked.bytes?.length ??
            int.tryParse(
              picked.entry?.artifact['size_bytes']?.toString() ?? '',
            ) ??
            0),
  );

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: IiOsRadii.xlAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: IiOsWidths.prose,
          maxHeight: IiOsWidths.prose,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PickerHeader(
              title: widget.title,
              source: _source,
              allowUpload: widget.allowUpload,
              onSource: (source) => setState(() => _source = source),
              onClose: () => Navigator.of(context).pop(),
            ),
            Divider(height: 1, color: palette.border),
            Flexible(
              child: _source == MediaPickerSource.library
                  ? MediaLibraryGrid(
                      history: widget.history,
                      loadPreview: widget.loadPreview,
                      contentTypePrefix: widget.contentTypePrefix,
                      multiple: widget.multiple,
                      chosen: _chosen.keys.toSet(),
                      onPick: widget.multiple
                          ? _toggle
                          : (entry) => Navigator.of(
                              context,
                            ).pop(PickedMedia.fromLibrary(entry)),
                    )
                  : MediaUploadPane(
                      types: widget.uploadTypes,
                      multiple: widget.multiple,
                      maxFileBytes: widget.maxUploadBytes,
                      maxTotalBytes: widget.maxTotalUploadBytes,
                      existingBytes: _chosenBytes,
                      onPicked: _addUpload,
                    ),
            ),
            if (widget.multiple && _chosen.isNotEmpty) ...[
              Divider(height: 1, color: palette.border),
              Padding(
                padding: const EdgeInsets.all(IiOsSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(_chosen.clear),
                      child: const Text('Clear'),
                    ),
                    IiOsGap.hSm,
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_chosen.values.toList(growable: false)),
                      // The count is on the button so the number chosen is
                      // visible without counting ticks across a grid.
                      child: Text('Add ${_chosen.length}'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Title, source switch, and dismiss.
///
/// The switch is only offered when there is a choice to make: a field that
/// cannot accept an upload should not show a tab that leads nowhere.
class _PickerHeader extends StatelessWidget {
  const _PickerHeader({
    required this.title,
    required this.source,
    required this.allowUpload,
    required this.onSource,
    required this.onClose,
  });

  final String title;
  final MediaPickerSource source;
  final bool allowUpload;
  final ValueChanged<MediaPickerSource> onSource;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IiOsSpacing.lg,
        IiOsSpacing.md,
        IiOsSpacing.sm,
        IiOsSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (allowUpload) ...[
            SegmentedButton<MediaPickerSource>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: MediaPickerSource.library,
                  label: Text('Library'),
                  icon: Icon(LucideIcons.images, size: IiOsIconSize.sm),
                ),
                ButtonSegment(
                  value: MediaPickerSource.upload,
                  label: Text('Upload'),
                  icon: Icon(LucideIcons.upload, size: IiOsIconSize.sm),
                ),
              ],
              selected: {source},
              onSelectionChanged: (value) => onSource(value.first),
            ),
            IiOsGap.hSm,
          ],
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(
              LucideIcons.x,
              size: IiOsIconSize.md,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}
