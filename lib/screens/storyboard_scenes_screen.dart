import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../models/storyboard.dart';
import '../services/local_video_handle.dart';
import '../services/polling_cost_policy.dart';
import '../services/storyboard_video_preloader.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import '../widgets/storyboard_editor_components.dart';
import '../widgets/storyboard_scene_generation_loading.dart';

List<StoryboardPanelDraft> animatedStoryboardPanelsInOrder(
  Iterable<StoryboardPanelDraft> panels,
) => panels
    .where((panel) => panel.videoJobId != null && panel.videoArtifact != null)
    .toList(growable: false);

class StoryboardScenesScreen extends StatefulWidget {
  const StoryboardScenesScreen({
    required this.controller,
    required this.panels,
    required this.storyboardName,
    required this.onBack,
    required this.onRefresh,
    super.key,
  });

  final AppController controller;
  final List<StoryboardPanelDraft> panels;
  final String storyboardName;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;

  @override
  State<StoryboardScenesScreen> createState() => _StoryboardScenesScreenState();
}

class _StoryboardScenesScreenState extends State<StoryboardScenesScreen> {
  Timer? _refreshTimer;
  final _videoPreloader = StoryboardVideoPreloader();
  LocalVideoHandle? _videoHandle;
  String? _currentPanelId;
  String? _currentJobId;
  bool _refreshing = false;
  bool _showRefreshProgress = false;
  bool _advancing = false;
  int _loadGeneration = 0;
  Set<String> _knownReadyJobs = const {};
  String? _error;
  VideoPlayerController? get _video => _videoHandle?.controller;

  List<StoryboardPanelDraft> get _readyPanels =>
      animatedStoryboardPanelsInOrder(widget.panels);

  List<StoryboardPanelDraft> get _activePanels => widget.panels
      .where(
        (panel) =>
            panel.videoJobId != null &&
            isActiveStoryboardJobStatus(panel.videoStatus),
      )
      .toList(growable: false);

  StoryboardPanelDraft? get _currentPanel {
    final id = _currentPanelId;
    if (id == null) return null;
    for (final panel in widget.panels) {
      if (panel.id == id) return panel;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPanels());
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(StoryboardScenesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRefreshTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPanels());
  }

  void _syncRefreshTimer() {
    if (_activePanels.isEmpty) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    _refreshTimer ??= Timer.periodic(
      IiOsPollingCostPolicy.activeOperation,
      (_) => unawaited(_refresh(showProgress: false)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _videoPreloader.dispose();
    _loadGeneration++;
    final handle = _videoHandle;
    if (handle != null) {
      handle.controller.removeListener(_videoChanged);
      unawaited(handle.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _readyPanels;
    final active = _activePanels;
    return PageFrame(
      title: 'View scenes',
      subtitle:
          '${widget.storyboardName} · Animated panels play continuously in storyboard order.',
      actions: [
        IconButton(
          tooltip: 'Back to storyboard',
          onPressed: widget.onBack,
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
        ),
        StatusPill('${ready.length}/${widget.panels.length} animated'),
        OutlinedButton.icon(
          onPressed: _refreshing ? null : _refresh,
          icon: _showRefreshProgress
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 17),
          label: const Text('Refresh'),
        ),
      ],
      child: ready.isEmpty && active.isNotEmpty
          ? StoryboardSceneGenerationLoading(
              count: active.length,
              expanded: true,
            )
          : ready.isEmpty
          ? const Card(
              child: EmptyState(
                title: 'No animated scenes yet',
                message:
                    'Open a generated panel, describe how it should move, and animate it. Completed clips will appear here automatically.',
                icon: LucideIcons.clapperboard,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (active.isNotEmpty) ...[
                  StoryboardSceneGenerationLoading(count: active.length),
                  IiOsGap.vMd,
                ],
                _playerCard(ready),
                IiOsGap.vMd,
                _sceneRail(ready),
              ],
            ),
    );
  }

  Widget _playerCard(List<StoryboardPanelDraft> ready) {
    final panel = _currentPanel;
    final video = _video;
    final initialized = video?.value.isInitialized == true;
    final currentIndex = panel == null
        ? -1
        : ready.indexWhere((candidate) => candidate.id == panel.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: initialized
                  ? video!.value.aspectRatio.clamp(0.45, 2.4)
                  : 16 / 9,
              child: _playerSurface(video, initialized),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IiOsSpacing.md,
              IiOsSpacing.sm,
              IiOsSpacing.md,
              IiOsSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous scene',
                      onPressed: currentIndex > 0 ? _previous : null,
                      icon: const Icon(LucideIcons.skipBack, size: 20),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: initialized ? _togglePlayback : null,
                      icon: Icon(
                        video?.value.isPlaying == true
                            ? LucideIcons.pause
                            : LucideIcons.play,
                        size: 18,
                      ),
                      label: Text(
                        video?.value.isPlaying == true ? 'Pause' : 'Play cut',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next scene',
                      onPressed:
                          currentIndex >= 0 && currentIndex < ready.length - 1
                          ? _next
                          : null,
                      icon: const Icon(LucideIcons.skipForward, size: 20),
                    ),
                    IiOsGap.hXs,
                    Expanded(
                      child: Text(
                        panel == null
                            ? 'Preparing cut\u2026'
                            : 'Panel ${_panelNumber(panel)} · '
                                  '${currentIndex + 1} of ${ready.length}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      _cutDuration(ready),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ),
                if (initialized) ...[
                  IiOsGap.vXs,
                  VideoProgressIndicator(
                    video!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: IiOsColors.green,
                      bufferedColor: IiOsColors.muted,
                      backgroundColor: IiOsColors.border,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerSurface(VideoPlayerController? video, bool initialized) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.triangleAlert,
                color: IiOsColors.red,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              IiOsGap.vSm,
              OutlinedButton(
                onPressed: _currentPanel == null
                    ? null
                    : () => _loadPanel(_currentPanel!),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (!initialized || video == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(child: VideoPlayer(video));
  }

  Widget _sceneRail(List<StoryboardPanelDraft> ready) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Animated panels'),
            IiOsGap.vSm,
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ready.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final panel = ready[index];
                  final artifact = panel.imageArtifact;
                  final selected = panel.id == _currentPanelId;
                  return SizedBox(
                    width: 138,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(IiOsRadii.md),
                        side: BorderSide(
                          color: selected
                              ? IiOsColors.green
                              : IiOsColors.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _loadPanel(panel),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (artifact != null && panel.imageJobId != null)
                              StoryboardArtifactImage(
                                controller: widget.controller,
                                workspaceId: widget.controller.workspace!.id,
                                jobId: panel.imageJobId!,
                                artifact: artifact,
                              )
                            else
                              const ColoredBox(color: IiOsColors.canvas),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.78),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 10,
                              child: Text(
                                'Panel ${_panelNumber(panel)} · '
                                '${panel.videoDurationSeconds}s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh({bool showProgress = true}) async {
    if (!mounted || _refreshing) return;
    setState(() {
      _refreshing = true;
      _showRefreshProgress = showProgress;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _showRefreshProgress = false;
        });
      }
    }
  }

  Future<void> _syncPanels() async {
    if (!mounted) return;
    final ready = _readyPanels;
    final current = _currentPanel;
    final previousJobs = _knownReadyJobs;
    final readyJobs = {
      for (final panel in ready) '${panel.id}:${panel.videoJobId}',
    };
    final newlyReady = ready
        .where(
          (panel) => !previousJobs.contains('${panel.id}:${panel.videoJobId}'),
        )
        .toList(growable: false);
    _knownReadyJobs = readyJobs;
    if (ready.isEmpty) {
      _videoPreloader.clear();
      if (current != null) await _replaceVideo(null);
      if (mounted) setState(() {});
      return;
    }
    if (current == null ||
        !ready.any((candidate) => candidate.id == current.id)) {
      await _loadPanel(ready.first);
      return;
    }
    if (previousJobs.isNotEmpty && newlyReady.isNotEmpty) {
      await _loadPanel(newlyReady.last, autoplay: true);
      return;
    }
    if (_currentJobId != current.videoJobId) {
      await _loadPanel(current);
      return;
    }
    _preloadFollowing(current);
    setState(() {});
  }

  Future<void> _loadPanel(
    StoryboardPanelDraft panel, {
    bool autoplay = false,
  }) async {
    final jobId = panel.videoJobId;
    final artifact = panel.videoArtifact;
    final object = artifact?['path']?.toString() ?? '';
    if (jobId == null || object.isEmpty) return;
    final generation = ++_loadGeneration;
    final key = _videoKey(panel);
    if (_video?.value.isPlaying == true) unawaited(_video!.pause());
    setState(() {
      _currentPanelId = panel.id;
      _currentJobId = jobId;
      _error = null;
    });
    try {
      var next = await _videoPreloader.take(key);
      if (next == null) {
        _videoPreloader.preload(
          key: key,
          resolveHandle: () => _createVideoHandle(panel),
        );
        next = await _videoPreloader.take(key);
      }
      if (next == null) {
        throw const FormatException('The scene video is unavailable.');
      }
      if (!mounted || generation != _loadGeneration) {
        await next.dispose();
        return;
      }
      if (autoplay) await next.controller.play();
      if (!mounted || generation != _loadGeneration) {
        await next.dispose();
        return;
      }
      await _replaceVideo(next);
      if (!mounted || generation != _loadGeneration) return;
      _preloadFollowing(panel);
    } on Object catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error.toString());
      }
    }
  }

  String _videoKey(StoryboardPanelDraft panel) {
    final artifact = panel.videoArtifact!;
    return jsonEncode([
      widget.controller.workspace!.id,
      widget.controller.connection?.bucket ?? '',
      panel.videoJobId!,
      artifact['path']?.toString() ?? '',
      artifact['generation']?.toString() ?? '',
      artifact['size_bytes'],
      artifact['sha256'],
      artifact['content_type'],
    ]);
  }

  Future<LocalVideoHandle> _createVideoHandle(
    StoryboardPanelDraft panel,
  ) async {
    final media = await widget.controller.readVerifiedArtifact(
      workspaceId: widget.controller.workspace!.id,
      jobId: panel.videoJobId!,
      artifact: panel.videoArtifact!,
    );
    return LocalVideoHandle.create(
      path: '',
      bytes: media.bytes,
      contentType: media.detectedContentType,
    );
  }

  void _preloadFollowing(StoryboardPanelDraft panel) {
    final ready = _readyPanels;
    final index = ready.indexWhere((candidate) => candidate.id == panel.id);
    if (index < 0 || index >= ready.length - 1) {
      _videoPreloader.clear();
      return;
    }
    final next = ready[index + 1];
    _videoPreloader.preload(
      key: _videoKey(next),
      resolveHandle: () => _createVideoHandle(next),
    );
  }

  Future<void> _replaceVideo(LocalVideoHandle? next) async {
    final previous = _videoHandle;
    previous?.controller.removeListener(_videoChanged);
    _videoHandle = next;
    next?.controller.addListener(_videoChanged);
    if (previous != null && previous != next) {
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      await previous.dispose();
    }
  }

  void _videoChanged() {
    final video = _video;
    if (!mounted || video == null) return;
    setState(() {});
    if (video.value.isCompleted && !_advancing) {
      _advancing = true;
      unawaited(_advanceAfterCompletion());
    }
  }

  Future<void> _advanceAfterCompletion() async {
    try {
      final ready = _readyPanels;
      final current = _currentPanel;
      if (current == null) return;
      final index = ready.indexWhere((panel) => panel.id == current.id);
      if (index >= 0 && index < ready.length - 1) {
        await _loadPanel(ready[index + 1], autoplay: true);
      }
    } finally {
      _advancing = false;
    }
  }

  void _togglePlayback() {
    final video = _video;
    if (video == null) return;
    if (video.value.isCompleted) {
      unawaited(video.seekTo(Duration.zero).then((_) => video.play()));
    } else if (video.value.isPlaying) {
      unawaited(video.pause());
    } else {
      unawaited(video.play());
    }
  }

  void _previous() {
    final ready = _readyPanels;
    final current = _currentPanel;
    if (current == null) return;
    final index = ready.indexWhere((panel) => panel.id == current.id);
    if (index > 0) unawaited(_loadPanel(ready[index - 1]));
  }

  void _next() {
    final ready = _readyPanels;
    final current = _currentPanel;
    if (current == null) return;
    final index = ready.indexWhere((panel) => panel.id == current.id);
    if (index >= 0 && index < ready.length - 1) {
      unawaited(_loadPanel(ready[index + 1]));
    }
  }

  int _panelNumber(StoryboardPanelDraft panel) =>
      widget.panels.indexWhere((candidate) => candidate.id == panel.id) + 1;

  String _cutDuration(List<StoryboardPanelDraft> ready) {
    final seconds = ready.fold<int>(
      0,
      (total, panel) => total + panel.videoDurationSeconds,
    );
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')} cut';
  }
}
