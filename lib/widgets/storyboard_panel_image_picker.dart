import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/storyboard.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';
import 'storyboard_editor_components.dart';

class StoryboardPanelImagePicker extends StatefulWidget {
  const StoryboardPanelImagePicker({
    required this.controller,
    required this.storyboardId,
    required this.panel,
    required this.generating,
    required this.canSelect,
    required this.onBeforeSelect,
    required this.onStoryboardChanged,
    super.key,
  });

  final AppController controller;
  final String storyboardId;
  final StoryboardPanelDraft panel;
  final bool generating;
  final bool canSelect;
  final Future<bool> Function() onBeforeSelect;
  final ValueChanged<StoryboardModel> onStoryboardChanged;

  @override
  State<StoryboardPanelImagePicker> createState() =>
      _StoryboardPanelImagePickerState();
}

class _StoryboardPanelImagePickerState
    extends State<StoryboardPanelImagePicker> {
  List<StoryboardPanelImageModel> _images = const [];
  bool _loading = false;
  String? _selectingPath;
  String? _error;

  String get _path =>
      'v1/workspaces/${widget.controller.workspace!.id}/storyboards/'
      '${widget.storyboardId}/panels/${widget.panel.id}';

  @override
  void initState() {
    super.initState();
    if (widget.panel.generationJobIds.isNotEmpty ||
        widget.panel.jobId != null) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(StoryboardPanelImagePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel.id != widget.panel.id ||
        oldWidget.panel.jobId != widget.panel.jobId ||
        oldWidget.panel.status != widget.panel.status ||
        oldWidget.panel.selectedImage?['path'] !=
            widget.panel.selectedImage?['path']) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.generating || isActiveStoryboardJobStatus(widget.panel.status);
    final selectedHistory = _selectedHistoryImage;
    final artifact = active
        ? null
        : selectedHistory?.artifact ?? widget.panel.imageArtifact;
    final imageJobId = active
        ? widget.panel.jobId
        : selectedHistory?.jobId ?? widget.panel.imageJobId;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IiOsColors.canvas,
        border: Border.all(color: IiOsColors.border),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Panel image history',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh panel images',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                ),
              ],
            ),
            Text(
              'Choose the image used for this panel and its animation.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: active
                    ? const _PendingPanelImage(large: true)
                    : artifact != null && imageJobId != null
                    ? StoryboardArtifactImage(
                        key: ValueKey(
                          'storyboard-panel-main-${widget.panel.id}-$imageJobId-'
                          '${artifact['path']}',
                        ),
                        controller: widget.controller,
                        workspaceId: widget.controller.workspace!.id,
                        jobId: imageJobId,
                        artifact: artifact,
                      )
                    : const ColoredBox(
                        color: IiOsColors.surface,
                        child: Center(
                          child: Icon(
                            LucideIcons.imagePlus,
                            color: IiOsColors.muted,
                            size: 30,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(height: 76, child: _history()),
            if (_error != null) ...[
              IiOsGap.vXs,
              Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: IiOsColors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _history() {
    final pending =
        widget.generating || isActiveStoryboardJobStatus(widget.panel.status);
    if (_loading && _images.isEmpty && !pending) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_images.isEmpty && !pending) {
      return const Center(
        child: Text(
          'Generated images will appear here.',
          style: TextStyle(color: IiOsColors.muted, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _images.length + (pending ? 1 : 0),
      separatorBuilder: (_, _) => IiOsGap.hXs,
      itemBuilder: (context, index) {
        if (pending && index == 0) {
          return const SizedBox(width: 96, child: _PendingPanelImage());
        }
        final image = _images[index - (pending ? 1 : 0)];
        final selecting = _selectingPath == image.path;
        return Semantics(
          button: true,
          selected: image.selected,
          label: 'Use ${image.filename} for this panel',
          child: Material(
            key: ValueKey('storyboard-panel-history-${image.path}'),
            color: IiOsColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IiOsRadii.md),
              side: BorderSide(
                color: image.selected ? IiOsColors.green : IiOsColors.border,
                width: image.selected ? 3 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap:
                  widget.canSelect &&
                      !pending &&
                      _selectingPath == null &&
                      !image.selected
                  ? () => _select(image)
                  : null,
              child: SizedBox(
                width: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StoryboardArtifactImage(
                      controller: widget.controller,
                      workspaceId: widget.controller.workspace!.id,
                      jobId: image.jobId,
                      artifact: image.artifact,
                    ),
                    if (selecting)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (image.selected)
                      const Positioned(
                        right: 4,
                        bottom: 4,
                        child: Icon(
                          LucideIcons.circleCheck,
                          color: IiOsColors.green,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await widget.controller.api.get('$_path/images');
      final images = (response['images'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .map(StoryboardPanelImageModel.fromJson)
          .toList();
      if (mounted) {
        setState(() {
          _images = images;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(StoryboardPanelImageModel image) async {
    if (!await widget.onBeforeSelect() || !mounted) return;
    final previousImages = _images;
    setState(() {
      _selectingPath = image.path;
      _images = [
        for (final candidate in _images)
          _withStoryboardImageSelection(
            candidate,
            candidate.jobId == image.jobId &&
                candidate.path == image.path &&
                candidate.generation == image.generation,
          ),
      ];
      _error = null;
    });
    try {
      final response = await widget.controller.api.patch(
        '$_path/selected-image',
        body: {
          'jobId': image.jobId,
          'path': image.path,
          'generation': image.generation,
        },
      );
      final model = StoryboardModel.fromJson(asJsonMap(response['data']));
      widget.onStoryboardChanged(model);
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _images = previousImages);
        showFailure(context, error);
      }
    } finally {
      if (mounted) setState(() => _selectingPath = null);
    }
  }

  StoryboardPanelImageModel? get _selectedHistoryImage {
    for (final image in _images) {
      if (image.selected) return image;
    }
    return null;
  }
}

class _PendingPanelImage extends StatelessWidget {
  const _PendingPanelImage({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'A new storyboard panel image is being generated.',
    child: ColoredBox(
      color: IiOsColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: large ? 28 : 20,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: large ? 10 : 5),
            Text(
              large ? 'Generating new panel image\u2026' : 'Creating new image',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: large ? 13 : 10),
            ),
          ],
        ),
      ),
    ),
  );
}

StoryboardPanelImageModel _withStoryboardImageSelection(
  StoryboardPanelImageModel image,
  bool selected,
) => StoryboardPanelImageModel(
  jobId: image.jobId,
  path: image.path,
  generation: image.generation,
  contentType: image.contentType,
  sizeBytes: image.sizeBytes,
  sha256: image.sha256,
  selected: selected,
  createdAt: image.createdAt,
);
