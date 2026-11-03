import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/storyboard.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';
import 'storyboard_animation_action.dart';
import 'storyboard_editor_components.dart';

const storyboardPanelReorderDelay = Duration(seconds: 1);

class StoryboardPanelGrid extends StatelessWidget {
  const StoryboardPanelGrid({
    required this.controller,
    required this.workspaceId,
    required this.panels,
    required this.selected,
    required this.generatingPanelId,
    required this.canAnimateSelected,
    required this.onSelect,
    required this.onAnimateSelected,
    this.onReorder,
    super.key,
  });

  final AppController controller;
  final String workspaceId;
  final List<StoryboardPanelDraft> panels;
  final int selected;
  final String? generatingPanelId;
  final bool canAnimateSelected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAnimateSelected;
  final ReorderCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(1, math.min(3, constraints.maxWidth ~/ 190));
        final extent = math.min(
          280.0,
          (constraints.maxWidth - (columns - 1) * 12) / columns,
        );
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1,
          children: [
            for (var index = 0; index < panels.length; index++)
              _ReorderablePanelTile(
                key: ValueKey('storyboard-panel-${panels[index].id}'),
                index: index,
                columns: columns,
                feedbackExtent: extent,
                onReorder: onReorder,
                child: _StoryboardPanelTile(
                  controller: controller,
                  workspaceId: workspaceId,
                  panel: panels[index],
                  panelNumber: index + 1,
                  selected: index == selected,
                  generating: generatingPanelId == panels[index].id,
                  canAnimate: canAnimateSelected,
                  reorderable: onReorder != null,
                  onTap: () => onSelect(index),
                  onAnimate: onAnimateSelected,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReorderablePanelTile extends StatefulWidget {
  const _ReorderablePanelTile({
    required this.index,
    required this.columns,
    required this.feedbackExtent,
    required this.onReorder,
    required this.child,
    super.key,
  });

  final int index;
  final int columns;
  final double feedbackExtent;
  final ReorderCallback? onReorder;
  final _StoryboardPanelTile child;

  @override
  State<_ReorderablePanelTile> createState() => _ReorderablePanelTileState();
}

class _ReorderablePanelTileState extends State<_ReorderablePanelTile> {
  bool _dropAfter = false;
  ScrollableState? _scrollable;
  EdgeDraggingAutoScroller? _autoScroller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == _scrollable) return;
    _autoScroller?.stopAutoScroll();
    _scrollable = scrollable;
    _autoScroller = scrollable == null
        ? null
        : EdgeDraggingAutoScroller(scrollable, velocityScalar: 50);
  }

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onReorder = widget.onReorder;
    if (onReorder == null) return widget.child;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != widget.index,
      onMove: _updateDropSide,
      onLeave: (_) => _clearDropSide(),
      onAcceptWithDetails: (details) {
        final destination = widget.index + (_dropAfter ? 1 : 0);
        _clearDropSide();
        onReorder(details.data, destination);
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            LongPressDraggable<int>(
              data: widget.index,
              delay: storyboardPanelReorderDelay,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragUpdate: (details) =>
                  _autoScroller?.startAutoScrollIfNecessary(
                    Rect.fromCenter(
                      center: details.globalPosition,
                      width: 40,
                      height: 40,
                    ),
                  ),
              onDragEnd: (_) => _autoScroller?.stopAutoScroll(),
              feedback: _PanelDragFeedback(
                panelNumber: widget.child.panelNumber,
                prompt: widget.child.panel.prompt.text,
                extent: widget.feedbackExtent,
              ),
              childWhenDragging: Opacity(opacity: 0.32, child: widget.child),
              child: widget.child,
            ),
            if (active)
              _DropIndicator(vertical: widget.columns == 1, after: _dropAfter),
          ],
        );
      },
    );
  }

  void _updateDropSide(DragTargetDetails<int> details) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(details.offset);
    final after = widget.columns == 1
        ? local.dy >= box.size.height / 2
        : local.dx >= box.size.width / 2;
    if (after != _dropAfter) setState(() => _dropAfter = after);
  }

  void _clearDropSide() {
    if (_dropAfter && mounted) setState(() => _dropAfter = false);
  }
}

class _DropIndicator extends StatelessWidget {
  const _DropIndicator({required this.vertical, required this.after});

  final bool vertical;
  final bool after;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: vertical ? 0 : (after ? null : -3),
      right: vertical ? 0 : (after ? -3 : null),
      top: vertical ? (after ? null : -3) : 0,
      bottom: vertical ? (after ? -3 : null) : 0,
      child: IgnorePointer(
        child: Container(
          width: vertical ? null : 6,
          height: vertical ? 6 : null,
          decoration: BoxDecoration(
            color: IiOsColors.blue,
            borderRadius: BorderRadius.circular(IiOsRadii.pill),
            boxShadow: [
              BoxShadow(
                color: IiOsColors.blue.withValues(alpha: 0.28),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelDragFeedback extends StatelessWidget {
  const _PanelDragFeedback({
    required this.panelNumber,
    required this.prompt,
    required this.extent,
  });

  final int panelNumber;
  final String prompt;
  final double extent;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: IiOsColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: extent,
        height: extent,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: IiOsColors.blue, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.gripVertical, color: IiOsColors.blue),
            IiOsGap.vXs,
            Text(
              'Panel $panelNumber',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (prompt.trim().isNotEmpty) ...[
              IiOsGap.vXs,
              Text(
                prompt.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoryboardPanelTile extends StatelessWidget {
  const _StoryboardPanelTile({
    required this.controller,
    required this.workspaceId,
    required this.panel,
    required this.panelNumber,
    required this.selected,
    required this.generating,
    required this.canAnimate,
    required this.reorderable,
    required this.onTap,
    required this.onAnimate,
  });

  final AppController controller;
  final String workspaceId;
  final StoryboardPanelDraft panel;
  final int panelNumber;
  final bool selected;
  final bool generating;
  final bool canAnimate;
  final bool reorderable;
  final VoidCallback onTap;
  final VoidCallback onAnimate;

  @override
  Widget build(BuildContext context) {
    final artifact = panel.imageArtifact;
    final active = isActiveStoryboardJobStatus(panel.status);
    return Material(
      color: IiOsColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IiOsRadii.md),
        side: BorderSide(
          color: selected ? IiOsColors.green : IiOsColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!active && artifact != null && panel.imageJobId != null)
              StoryboardArtifactImage(
                controller: controller,
                workspaceId: workspaceId,
                jobId: panel.imageJobId!,
                artifact: artifact,
              )
            else
              ColoredBox(
                color: IiOsColors.canvas,
                child: Center(
                  child: generating || active
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          panel.jobId == null
                              ? LucideIcons.imagePlus
                              : LucideIcons.loaderCircle,
                          size: 30,
                          color: IiOsColors.muted,
                        ),
                ),
              ),
            Positioned(
              left: 8,
              top: 8,
              right: 8,
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TileLabel(label: 'Panel $panelNumber'),
                    if (selected) ...[
                      IiOsGap.hXs,
                      Expanded(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: StoryboardAnimationAction(
                            hasVideo: panel.videoArtifact != null,
                            isAnimating: const {
                              'dispatching',
                              'dispatched',
                              'queued',
                              'requested',
                              'in_progress',
                              'running',
                            }.contains(panel.videoStatus),
                            canAnimate: canAnimate,
                            compact: constraints.maxWidth < 230,
                            onAnimate: onAnimate,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (reorderable)
              const Positioned(
                left: 8,
                bottom: 8,
                child: Tooltip(
                  message: 'Hold for 1 second, then drag to reorder',
                  child: _DragHandle(),
                ),
              ),
            Positioned(right: 8, bottom: 8, child: StatusPill(panel.status)),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IiOsColors.charcoal.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(IiOsRadii.sm),
      ),
      child: const Padding(
        padding: EdgeInsets.all(5),
        child: Icon(LucideIcons.gripVertical, color: Colors.white, size: 16),
      ),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IiOsColors.charcoal.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(IiOsRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
