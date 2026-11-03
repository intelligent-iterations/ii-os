import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/storyboard.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'storyboard_editor_screen.dart';

class StoryboardsScreen extends StatefulWidget {
  const StoryboardsScreen({
    required this.controller,
    this.selectedStoryboardId,
    this.selectedPanelId,
    this.selectedView,
    this.onSelectStoryboard,
    this.onCloseStoryboard,
    this.onPanelChanged,
    this.onViewChanged,
    this.onJobViewed,
    super.key,
  });

  final AppController controller;
  final String? selectedStoryboardId;
  final String? selectedPanelId;
  final String? selectedView;
  final ValueChanged<String>? onSelectStoryboard;
  final VoidCallback? onCloseStoryboard;
  final ValueChanged<String>? onPanelChanged;
  final ValueChanged<String?>? onViewChanged;
  final ValueChanged<String>? onJobViewed;

  @override
  State<StoryboardsScreen> createState() => _StoryboardsScreenState();
}

class _StoryboardsScreenState extends State<StoryboardsScreen> {
  List<StoryboardModel> _storyboards = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  bool get _canEdit => widget.controller.can('jobs.trigger');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedStoryboardId;
    if (selectedId != null) {
      return StoryboardEditorScreen(
        key: ValueKey(selectedId),
        controller: widget.controller,
        storyboardId: selectedId,
        selectedPanelId: widget.selectedPanelId,
        selectedView: widget.selectedView,
        onPanelChanged: widget.onPanelChanged,
        onViewChanged: widget.onViewChanged,
        onBack: _returnToList,
        onDeleted: _returnToList,
      );
    }
    return PageFrame(
      title: 'Storyboards',
      subtitle: 'Create, view, and edit storyboards in this workspace',
      actions: [
        IconButton(
          tooltip: 'Refresh storyboards',
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
        ),
        if (_canEdit)
          FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.plus, size: 17),
            label: const Text('New storyboard'),
          ),
      ],
      child: _body(),
    );
  }

  Widget _body() {
    // A failed *refresh* keeps the list on screen; only a failed first load
    // replaces it.
    if (_error != null && _storyboards.isEmpty) {
      return ErrorSurface(
        title: 'Storyboards could not be loaded',
        message: _error!,
        onRetry: _load,
      );
    }
    // Gated on the list being empty so a refresh never blanks storyboards the
    // operator is already looking at.
    if (_loading && _storyboards.isEmpty) {
      return const LoadingSurface(label: 'Loading storyboards');
    }
    if (_storyboards.isEmpty) {
      return EmptyState(
        title: 'No storyboards yet',
        message:
            'Create a storyboard, describe the whole story in 150 words or fewer, then build 3 to 9 image panels.',
        icon: LucideIcons.panelsTopLeft,
        action: !_canEdit
            ? null
            : FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: const Icon(LucideIcons.plus, size: 17),
                label: const Text('New storyboard'),
              ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: IiOsColors.surface,
        border: Border.all(color: IiOsColors.border),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _storyboards.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) => _StoryboardRow(
          storyboard: _storyboards[index],
          onTap: () => widget.onSelectStoryboard?.call(_storyboards[index].id),
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await widget.controller.api.get(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards',
      );
      final storyboards =
          (response['storyboards'] as List<Object?>? ?? const [])
              .map(asJsonMap)
              .map(StoryboardModel.fromJson)
              .toList();
      if (!mounted) return;
      for (final storyboard in storyboards) {
        for (final panel in storyboard.panels) {
          for (final jobId in [...panel.generationJobIds, ?panel.videoJobId]) {
            widget.onJobViewed?.call(jobId);
          }
        }
      }
      setState(() {
        _storyboards = storyboards;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final response = await widget.controller.api.post(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards',
        body: {
          'name': _nextStoryboardName(),
          'overview': '',
          'panelCount': storyboardMinimumPanels,
        },
      );
      final storyboard = StoryboardModel.fromJson(asJsonMap(response['data']));
      if (!mounted) return;
      widget.onSelectStoryboard?.call(storyboard.id);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _nextStoryboardName() {
    var number = _storyboards.length + 1;
    final names = _storyboards.map((storyboard) => storyboard.name).toSet();
    while (names.contains('Storyboard $number')) {
      number++;
    }
    return 'Storyboard $number';
  }

  void _returnToList() {
    widget.onCloseStoryboard?.call();
    _load();
  }
}

class _StoryboardRow extends StatelessWidget {
  const _StoryboardRow({required this.storyboard, required this.onTap});

  final StoryboardModel storyboard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: IiOsColors.canvas,
                  borderRadius: BorderRadius.all(Radius.circular(IiOsRadii.md)),
                ),
                child: Icon(
                  LucideIcons.panelsTopLeft,
                  size: 20,
                  color: IiOsColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storyboard.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    storyboard.overview.isEmpty
                        ? 'No story overview yet'
                        : storyboard.overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IiOsGap.hMd,
            Text(
              '${storyboard.panels.length} panels',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.hMd,
            if (MediaQuery.sizeOf(context).width >= 680) ...[
              Text(
                _shortDate(storyboard.updatedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IiOsGap.hSm,
            ],
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
      ),
    );
  }
}

String _shortDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
