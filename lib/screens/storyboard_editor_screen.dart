import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../models/character.dart';
import '../models/models.dart';
import '../models/storyboard.dart';
import '../models/storyboard_character_workflow.dart';
import '../services/polling_cost_policy.dart';
import '../services/storyboard_panel_extend_service.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import '../widgets/storyboard_editor_components.dart';
import '../widgets/storyboard_panel_extend_picker.dart';
import '../widgets/storyboard_panel_grid.dart';
import '../widgets/storyboard_panel_image_picker.dart';
import '../widgets/storyboard_panel_reference_options.dart';
import 'storyboard_panel_animation_screen.dart';
import 'storyboard_scenes_screen.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../state/prompt_enhance_host.dart';
import '../state/prompt_enhancement_fields.dart';
import '../widgets/prompt_enhance_bar.dart';

class StoryboardEditorScreen extends StatefulWidget {
  const StoryboardEditorScreen({
    required this.controller,
    required this.storyboardId,
    required this.onBack,
    required this.onDeleted,
    this.selectedPanelId,
    this.selectedView,
    this.onPanelChanged,
    this.onViewChanged,
    super.key,
  });

  final AppController controller;
  final String storyboardId;
  final VoidCallback onBack;
  final VoidCallback onDeleted;
  final String? selectedPanelId;
  final String? selectedView;
  final ValueChanged<String>? onPanelChanged;
  final ValueChanged<String?>? onViewChanged;

  @override
  State<StoryboardEditorScreen> createState() => _StoryboardEditorScreenState();
}

class _StoryboardEditorScreenState extends State<StoryboardEditorScreen> {
  final _name = TextEditingController();
  final _overview = TextEditingController();
  late final PromptEnhanceHost _enhancements = PromptEnhanceHost(
    fields: PromptEnhancementFields(
      repository: PromptEnhancementApiRepository(widget.controller.api),
      workspaceId: widget.controller.workspace!.id,
    ),
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  Timer? _timer;
  List<StoryboardPanelDraft> _panels = [];
  List<CharacterModel> _characters = const [];
  List<WorkflowTemplateModel> _templates = const [];
  int _selectedPanel = 0;
  bool _loading = true;
  bool _loadingCharacters = true;
  bool _loadingTemplates = true;
  bool _saving = false;
  bool _dirty = false;
  String? _generatingPanelId;
  String? _extendingPanelId;
  String? _error;
  late final _extendService = StoryboardPanelExtendService(
    controller: widget.controller,
  );

  bool get _canEdit => widget.controller.can('jobs.trigger');

  WorkflowTemplateModel? _selectedTemplateFor(StoryboardPanelDraft panel) {
    return storyboardGenerationTemplate(
      characterIds: panel.characterIds,
      characters: _characters,
      templates: _templates,
      hasPanelReference: panel.referencePanelIds.isNotEmpty,
    );
  }

  /// The rewrite affordance for one storyboard field.
  ///
  /// Both fields describe pictures the panel model will render, so both resolve
  /// their guide through the template that panel generates with. Only a panel
  /// prompt carries the continuity rules: the overview is written once for the
  /// whole story, not to keep a cast recognisable between two images.
  PromptEnhanceBinding? _enhanceBinding({
    required String stateKey,
    required StoryboardPanelDraft panel,
    required bool storyboardPanel,
  }) {
    final template = _selectedTemplateFor(panel);
    if (template == null) return null;
    return _enhancements.binding(
      field: 'prompt',
      stateKey: stateKey,
      workflowId: template.workflowId,
      targetModel: template.model,
      maxLength: template.inputs['prompt']?.maxLength ?? 4000,
      storyboardPanel: storyboardPanel,
    );
  }

  bool _panelHasSelectedReference(StoryboardPanelDraft panel) =>
      panel.referencePanelIds.isNotEmpty ||
      storyboardHasSelectedCharacterReference(
        characterIds: panel.characterIds,
        characters: _characters,
      );

  @override
  void initState() {
    super.initState();
    _loadStoryboard();
    _loadCharacters();
    _loadTemplates();
    _timer = Timer.periodic(IiOsPollingCostPolicy.activeOperation, (_) {
      if (_hasActiveJobs) _loadStoryboard(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _overview.dispose();
    for (final panel in _panels) {
      panel.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StoryboardEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPanelId != widget.selectedPanelId) {
      final index = _panels.indexWhere(
        (panel) => panel.id == widget.selectedPanelId,
      );
      if (index >= 0 && index != _selectedPanel) {
        setState(() => _selectedPanel = index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gated on there being no panels yet, so a background refresh never
    // blanks the storyboard the operator is editing.
    if (_loading && _panels.isEmpty) {
      return const LoadingSurface(label: 'Loading storyboard');
    }
    if (_error != null && _panels.isEmpty) {
      return PageFrame(
        title: 'Storyboard',
        actions: [
          IconButton(
            tooltip: 'Back to storyboards',
            onPressed: widget.onBack,
            icon: const Icon(LucideIcons.arrowLeft, size: 18),
          ),
        ],
        child: EmptyState(
          title: 'Storyboard could not be loaded',
          message: _error!,
          icon: LucideIcons.triangleAlert,
          action: FilledButton(
            onPressed: _loadStoryboard,
            child: const Text('Retry'),
          ),
        ),
      );
    }
    final selected = _panels[_selectedPanel];
    if (widget.selectedView == 'animate') {
      return StoryboardPanelAnimationScreen(
        controller: widget.controller,
        storyboardId: widget.storyboardId,
        panel: selected,
        panelNumber: _selectedPanel + 1,
        templates: _templates,
        loadingTemplates: _loadingTemplates,
        canEdit: _canEdit,
        onBack: _closeSubview,
        onViewScenes: _viewScenes,
        onStoryboardChanged: _acceptStoryboard,
      );
    }
    if (widget.selectedView == 'scenes') {
      return StoryboardScenesScreen(
        controller: widget.controller,
        panels: _panels,
        storyboardName: _name.text,
        onBack: _closeSubview,
        onRefresh: () => _loadStoryboard(quiet: true),
      );
    }
    return PageFrame(
      title: 'Edit storyboard',
      subtitle:
          'Tap a panel to edit it. Hold for 1 second, then drag to reorder the cut.',
      actions: [
        IconButton(
          tooltip: 'Back to storyboards',
          onPressed: _saving ? null : _back,
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
        ),
        if (_canEdit)
          IconButton(
            tooltip: 'Delete storyboard',
            onPressed: _saving ? null : _delete,
            icon: const Icon(LucideIcons.trash2, size: 18),
          ),
        if (_canEdit)
          FilledButton.icon(
            onPressed: _saving || !_dirty ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.save, size: 17),
            label: const Text('Save'),
          ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _viewScenes,
          icon: const Icon(LucideIcons.clapperboard, size: 17),
          label: const Text('View scenes'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            enabled: _canEdit && !_saving,
            maxLength: 100,
            onChanged: (_) => _markDirty(),
            decoration: const InputDecoration(
              labelText: 'Storyboard name',
              prefixIcon: Icon(LucideIcons.panelsTopLeft, size: 18),
            ),
          ),
          IiOsGap.vMd,
          StoryboardOverviewField(
            controller: _overview,
            enabled: _canEdit && !_saving,
            onChanged: _markDirty,
            promptEnhance: _panels.isEmpty
                ? null
                : _enhanceBinding(
                    stateKey: 'overview',
                    panel: _panels[_selectedPanel],
                    storyboardPanel: false,
                  ),
          ),
          IiOsGap.vMd,
          StoryboardPanelCountBar(
            count: _panels.length,
            onAdd: !_canEdit || _panels.length >= storyboardMaximumPanels
                ? null
                : _addPanel,
            onRemove: !_canEdit || _panels.length <= storyboardMinimumPanels
                ? null
                : _removePanel,
          ),
          IiOsGap.vMd,
          LayoutBuilder(
            builder: (context, constraints) {
              final grid = StoryboardPanelGrid(
                controller: widget.controller,
                workspaceId: widget.controller.workspace!.id,
                panels: _panels,
                selected: _selectedPanel,
                generatingPanelId: _generatingPanelId,
                canAnimateSelected:
                    _canEdit &&
                    !_saving &&
                    selected.imageJobId != null &&
                    selected.imageArtifact != null,
                onSelect: _selectPanel,
                onAnimateSelected: _openAnimation,
                onReorder: !_canEdit || _saving ? null : _reorderPanel,
              );
              final editor = StoryboardPanelEditor(
                controller: widget.controller,
                panel: selected,
                panelNumber: _selectedPanel + 1,
                characters: _characters,
                panelReferences: storyboardPanelReferenceOptions(
                  panels: _panels,
                  controller: widget.controller,
                  workspaceId: widget.controller.workspace!.id,
                ),
                loadingCharacters: _loadingCharacters,
                enabled: _canEdit,
                generating: _generatingPanelId == selected.id,
                promptEnhance: _enhanceBinding(
                  stateKey: 'panel:${selected.id}',
                  panel: selected,
                  storyboardPanel: true,
                ),
                canGenerate:
                    _canEdit &&
                    !_saving &&
                    !_loadingCharacters &&
                    !_loadingTemplates &&
                    _selectedTemplateFor(selected)?.enabled == true &&
                    selected.prompt.text.trim().isNotEmpty &&
                    storyboardWordCount(_overview.text) <=
                        storyboardOverviewWordLimit,
                onChanged: _markDirty,
                onGenerate: () => _generatePanel(_selectedPanel),
                imagePicker: StoryboardPanelImagePicker(
                  key: ValueKey('panel-picker-${selected.id}'),
                  controller: widget.controller,
                  storyboardId: widget.storyboardId,
                  panel: selected,
                  generating: _generatingPanelId == selected.id,
                  canSelect: _canEdit && !_saving,
                  onBeforeSelect: () async => !_dirty || await _save(),
                  onStoryboardChanged: _acceptStoryboard,
                ),
                extendPicker: StoryboardPanelExtendPicker(
                  key: ValueKey('panel-extend-${selected.id}'),
                  options: storyboardPanelExtendOptions(
                    panels: _panels,
                    currentPanelId: selected.id,
                    controller: widget.controller,
                    workspaceId: widget.controller.workspace!.id,
                  ),
                  extendedFromPanelId: selected.extendedFromPanelId,
                  extending: _extendingPanelId == selected.id,
                  enabled:
                      _canEdit &&
                      !_saving &&
                      _generatingPanelId == null &&
                      _extendingPanelId == null,
                  onExtend: (sourcePanelId) =>
                      _extendPanel(_selectedPanel, sourcePanelId),
                ),
                workflowNotice: storyboardWorkflowNotice(
                  context: context,
                  loadingTemplates: _loadingTemplates,
                  usesReference: _panelHasSelectedReference(selected),
                  template: _selectedTemplateFor(selected),
                ),
                runtimeEstimate: _selectedTemplateFor(
                  selected,
                )?.estimateRuntime(const {}),
              );
              if (constraints.maxWidth < 860) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [grid, IiOsGap.vMd, editor],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: grid),
                  IiOsGap.hMd,
                  Expanded(flex: 4, child: editor),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  bool get _hasActiveJobs => _panels.any((panel) {
    const active = {
      'dispatching',
      'dispatched',
      'queued',
      'requested',
      'in_progress',
      'running',
    };
    return active.contains(panel.status) || active.contains(panel.videoStatus);
  });

  Future<void> _loadStoryboard({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final response = await widget.controller.api.get(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards/${widget.storyboardId}',
      );
      final model = StoryboardModel.fromJson(asJsonMap(response['storyboard']));
      if (!mounted) return;
      setState(() {
        if (quiet && _dirty) {
          final byId = {for (final panel in model.panels) panel.id: panel};
          for (final panel in _panels) {
            final updated = byId[panel.id];
            if (updated != null) panel.mergeJob(updated);
          }
        } else {
          _replaceDraft(model);
        }
        _error = null;
      });
    } on Object catch (error) {
      if (mounted && !quiet) setState(() => _error = error.toString());
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _loadCharacters() async {
    try {
      final response = await widget.controller.api.get(
        'v1/workspaces/${widget.controller.workspace!.id}/characters',
      );
      final characters = (response['characters'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .map(CharacterModel.fromJson)
          .where(
            (character) =>
                !character.isDraft && character.selectedImage != null,
          )
          .toList();
      if (mounted) setState(() => _characters = characters);
    } on Object catch (_) {
      // Character attachments are optional; panel editing remains available.
    } finally {
      if (mounted) setState(() => _loadingCharacters = false);
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final response = await widget.controller.api.get(
        'v1/workspaces/${widget.controller.workspace!.id}/workflow-templates',
      );
      final templates = (response['templates'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .map(WorkflowTemplateModel.fromJson)
          .where(
            (template) =>
                template.workflowId.startsWith('image-create') ||
                template.workflowId == 'image-edit' ||
                template.workflowId.startsWith('image-edit-') ||
                template.workflowId == 'image-to-video',
          )
          .toList();
      if (mounted) setState(() => _templates = templates);
    } on Object catch (_) {
    } finally {
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  void _replaceDraft(StoryboardModel model) {
    final selectedPanelId = _panels.isEmpty
        ? widget.selectedPanelId
        : _panels[_selectedPanel].id;
    for (final panel in _panels) {
      panel.dispose();
    }
    _name.text = model.name;
    _overview.text = model.overview;
    _panels = model.panels.map(StoryboardPanelDraft.fromModel).toList();
    final requested = _panels.indexWhere(
      (panel) => panel.id == selectedPanelId,
    );
    _selectedPanel = requested >= 0
        ? requested
        : math.min(_selectedPanel, _panels.length - 1);
    _dirty = false;
    _publishSelectedPanel();
  }

  void _markDirty() => setState(() => _dirty = true);

  void _addPanel() {
    setState(() {
      _panels.add(
        StoryboardPanelDraft(
          id: const Uuid().v4(),
          prompt: '',
          characterIds: const {},
        ),
      );
      _selectedPanel = _panels.length - 1;
      _dirty = true;
    });
  }

  void _removePanel() {
    setState(() {
      final removed = _panels.removeLast();
      for (final panel in _panels) {
        panel.referencePanelIds.remove(removed.id);
      }
      removed.dispose();
      _selectedPanel = math.min(_selectedPanel, _panels.length - 1);
      _dirty = true;
    });
    _publishSelectedPanel();
  }

  void _selectPanel(int index) {
    setState(() => _selectedPanel = index);
    _publishSelectedPanel();
  }

  void _reorderPanel(int oldIndex, int destinationIndex) {
    if (oldIndex < 0 || oldIndex >= _panels.length) return;
    var newIndex = destinationIndex.clamp(0, _panels.length);
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    final selectedPanelId = _panels[_selectedPanel].id;
    setState(() {
      final panel = _panels.removeAt(oldIndex);
      _panels.insert(newIndex, panel);
      _selectedPanel = _panels.indexWhere(
        (candidate) => candidate.id == selectedPanelId,
      );
      _dirty = true;
    });
  }

  void _publishSelectedPanel() {
    if (_panels.isEmpty) return;
    final panelId = _panels[_selectedPanel].id;
    if (widget.selectedPanelId == panelId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPanelChanged?.call(panelId);
    });
  }

  Future<void> _openAnimation() async {
    if (_dirty && !await _save()) return;
    widget.onViewChanged?.call('animate');
  }

  Future<void> _viewScenes() async {
    if (_dirty && !await _save()) return;
    widget.onViewChanged?.call('scenes');
  }

  void _closeSubview() => widget.onViewChanged?.call(null);

  void _acceptStoryboard(StoryboardModel model) {
    if (!mounted) return;
    setState(() => _replaceDraft(model));
  }

  Future<bool> _save() async {
    if (_name.text.trim().isEmpty) {
      showFailure(context, const FormatException('Add a storyboard name.'));
      return false;
    }
    if (storyboardWordCount(_overview.text) > storyboardOverviewWordLimit) {
      showFailure(
        context,
        const FormatException('Keep the story overview to 150 words or fewer.'),
      );
      return false;
    }
    setState(() => _saving = true);
    try {
      final response = await widget.controller.api.patch(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards/${widget.storyboardId}',
        body: {
          'name': _name.text.trim(),
          'overview': _overview.text.trim(),
          'panels': _panels.map((panel) => panel.toJson()).toList(),
        },
      );
      final model = StoryboardModel.fromJson(asJsonMap(response['data']));
      if (!mounted) return false;
      setState(() => _replaceDraft(model));
      return true;
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generatePanel(int index) async {
    if (_dirty && !await _save()) return;
    final panel = _panels[index];
    final template = _selectedTemplateFor(panel);
    if (template == null || !template.enabled) return;
    setState(() => _generatingPanelId = panel.id);
    try {
      final response = await widget.controller.api.post(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards/${widget.storyboardId}/panels/${panel.id}/generate',
        body: {
          'workflowKey': template.id,
          if (_enhancements.fields.keptEnhancedTextFor('panel:${panel.id}'))
            'promptEnhancementBypass': 'user_enhanced',
          'input': template.workflowId.startsWith('image-edit')
              ? {'control_strength': 0.65}
              : {
                  'aspect_ratio': '1:1',
                  'model': ?storyboardGenerationModelInputFor(
                    template.workflowId,
                  ),
                },
        },
      );
      final data = asJsonMap(response['data']);
      final model = StoryboardModel.fromJson(asJsonMap(data['storyboard']));
      if (mounted) setState(() => _replaceDraft(model));
      await widget.controller.refreshDashboard();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
      await _loadStoryboard(quiet: true);
    } finally {
      if (mounted) setState(() => _generatingPanelId = null);
    }
  }

  Future<void> _extendPanel(int index, String sourcePanelId) async {
    if (_dirty && !await _save()) return;
    final panel = _panels[index];
    final sourcePanel = _panels.cast<StoryboardPanelDraft?>().firstWhere(
      (candidate) => candidate?.id == sourcePanelId,
      orElse: () => null,
    );
    if (sourcePanel == null) return;
    setState(() => _extendingPanelId = panel.id);
    try {
      final model = await _extendService.extendPanel(
        workspaceId: widget.controller.workspace!.id,
        storyboardId: widget.storyboardId,
        panelId: panel.id,
        sourcePanel: sourcePanel,
      );
      if (mounted) setState(() => _replaceDraft(model));
      await widget.controller.refreshDashboard();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _extendingPanelId = null);
    }
  }

  Future<void> _back() async {
    if (_dirty && !await _save()) return;
    widget.onBack();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete storyboard?'),
        content: const Text(
          'This removes the storyboard record. Generated jobs and artifacts remain in job history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.api.delete(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards/${widget.storyboardId}',
      );
      if (mounted) widget.onDeleted();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
