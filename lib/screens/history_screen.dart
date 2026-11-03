import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/generation_history.dart';
import '../navigation/app_route_state.dart';
import '../repositories/generation_history_repository.dart';
import '../state/app_controller.dart';
import '../widgets/artifact_preview.dart';
import '../widgets/artifact_thumbnail.dart';
import '../widgets/common.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

part 'history_content.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    required this.controller,
    this.onJobViewed,
    this.embedded = false,
    this.selectedJobId,
    this.selectedObject,
    super.key,
  });

  final AppController controller;
  final ValueChanged<String>? onJobViewed;
  final bool embedded;

  /// The run whose asset the URL asked for, when it named one.
  final String? selectedJobId;

  /// Which artifact of that run, for a run that produced more than one.
  final String? selectedObject;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final GenerationHistoryRepository _history;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final workspace = widget.controller.workspace!;
    _history = widget.controller.media.history(
      workspaceId: workspace.id,
      retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
    );
    _history.addListener(_changed);
    _scrollController.addListener(_loadNearEnd);
    _history.startWatching();
  }

  @override
  void dispose() {
    _history
      ..removeListener(_changed)
      ..stopWatching();
    _scrollController
      ..removeListener(_loadNearEnd)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    for (final jobId in _history.entries.map((entry) => entry.jobId).toSet()) {
      widget.onJobViewed?.call(jobId);
    }
    if (mounted) setState(() {});
  }

  void _loadNearEnd() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 720) {
      unawaited(_history.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final retention =
        widget.controller.workspace!.artifactStorage?.retentionDays ?? 30;
    final actions = [
      OutlinedButton.icon(
        onPressed: _history.initializing || _history.refreshing
            ? null
            : () => _history.refresh(reportError: true),
        icon: const Icon(LucideIcons.refreshCw, size: 17),
        label: const Text('Refresh'),
      ),
    ];
    final content = _content();
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Generated media · $retention-day retention',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...actions,
            ],
          ),
          IiOsGap.vSm,
          content,
        ],
      );
    }
    return PageFrame(
      title: 'Asset library',
      subtitle: 'Generated media · $retention-day retention',
      actions: actions,
      scrollController: _scrollController,
      child: content,
    );
  }

  Widget _content() {
    final error = _history.errorMessage;
    final entries = _history.entries;
    if (error != null && entries.isEmpty) {
      return EmptyState(
        title: 'The asset library could not be loaded',
        message: error,
        icon: LucideIcons.triangleAlert,
        action: FilledButton(
          onPressed: _history.loadInitial,
          child: const Text('Retry'),
        ),
      );
    }
    if (_history.initializing && entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (entries.isEmpty) {
      final hasOlderJobs = _history.hasMore;
      return EmptyState(
        title: hasOlderJobs
            ? 'No media in the newest jobs'
            : 'No generated media',
        message: hasOlderJobs
            ? 'Older generated media may still be available.'
            : 'Completed image, video, and audio jobs will appear here.',
        icon: LucideIcons.images,
        action: hasOlderJobs
            ? FilledButton.icon(
                onPressed: _history.loadingMore ? null : _history.loadMore,
                icon: _history.loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.chevronsDown, size: 17),
                label: const Text('Load older history'),
              )
            : null,
      );
    }
    return _HistoryGrid(
      controller: widget.controller,
      entries: entries,
      selectedJobId: widget.selectedJobId,
      selectedObject: widget.selectedObject,
      error: error,
      hasMore: _history.hasMore,
      loadingMore: _history.loadingMore,
      onLoadMore: _history.loadMore,
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.controller,
    required this.workspaceId,
    required this.entry,
    this.selected = false,
    super.key,
  });

  final AppController controller;
  final String workspaceId;
  final HistoryEntryModel entry;

  /// True when the URL named this asset, which is what a shared link lands on.
  final bool selected;

  /// The address of this asset.
  ///
  /// The run identifies it and the object name disambiguates a run that
  /// produced more than one, which is why the object rides as a query rather
  /// than a path segment: it contains slashes and is not one segment.
  String get _location => AppRouteState(
    workspaceId: workspaceId,
    page: AppPage.history,
    itemId: entry.jobId,
    query: {'object': entry.objectName},
  ).location;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final palette = IiOsPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: selected
          ? RoundedRectangleBorder(
              side: BorderSide(color: palette.accent.fill, width: 2),
              borderRadius: IiOsRadii.lgAll,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _preview()),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The prompt leads, because it is the only part a
                      // person recognises their own work by. A generated
                      // filename identifies the file, not the piece -- it moves
                      // to the tooltip beside the repository it came from.
                      Tooltip(
                        message: entry.repository.isEmpty
                            ? entry.filename
                            : '${entry.filename}\n${entry.repository}',
                        child: Text(
                          entry.generation.prompt.isEmpty
                              ? entry.filename
                              : entry.generation.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IiOsGap.vXs,
                      Wrap(
                        spacing: IiOsSpacing.xs,
                        runSpacing: IiOsSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(entry.status),
                          if (entry.generation.model.isNotEmpty)
                            IiOsMetaChip(label: entry.generation.model),
                          Text(
                            _shortDate(entry.submittedAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy link to this asset',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: Uri.base.resolve(_location).toString()),
                  ),
                  icon: const Icon(LucideIcons.link, size: 17),
                ),
                ArtifactPreviewAction(
                  load: () => controller.readVerifiedArtifact(
                    workspaceId: workspaceId,
                    jobId: entry.jobId,
                    artifact: entry.artifact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() => ArtifactThumbnail(
    identity: entry.identity,
    // Audio has no still to show, and a video generated before posters
    // existed has none either.
    load: entry.previewArtifact == null
        ? null
        : () => controller.readVerifiedArtifact(
            workspaceId: workspaceId,
            jobId: entry.jobId,
            artifact: entry.previewArtifact ?? entry.artifact,
          ),
    errorSource: 'history.thumbnail',
    placeholderIcon: entry.isAudio ? LucideIcons.audioLines : LucideIcons.play,
    // A poster makes the card legible, but it also makes a video look like a
    // still. The badge is what keeps the difference visible at a glance
    // across a grid that mixes both.
    overlay: entry.isVideo
        ? ArtifactPreviewAction(
            load: () => controller.readVerifiedArtifact(
              workspaceId: workspaceId,
              jobId: entry.jobId,
              artifact: entry.artifact,
            ),
            autoplay: true,
            presentation: ArtifactPreviewPresentation.play,
          )
        : null,
  );
}

String _shortDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
