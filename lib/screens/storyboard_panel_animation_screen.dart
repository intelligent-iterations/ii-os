import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show DurationSelector;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/storyboard.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import '../widgets/job_submission_result.dart';
import '../widgets/storyboard_editor_components.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../state/prompt_enhance_host.dart';
import '../state/prompt_enhancement_fields.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../widgets/runtime_estimate_notice.dart';

class StoryboardPanelAnimationScreen extends StatefulWidget {
  const StoryboardPanelAnimationScreen({
    required this.controller,
    required this.storyboardId,
    required this.panel,
    required this.panelNumber,
    required this.templates,
    required this.loadingTemplates,
    required this.canEdit,
    required this.onBack,
    required this.onViewScenes,
    required this.onStoryboardChanged,
    super.key,
  });

  final AppController controller;
  final String storyboardId;
  final StoryboardPanelDraft panel;
  final int panelNumber;
  final List<WorkflowTemplateModel> templates;
  final bool loadingTemplates;
  final bool canEdit;
  final VoidCallback onBack;
  final VoidCallback onViewScenes;
  final ValueChanged<StoryboardModel> onStoryboardChanged;

  @override
  State<StoryboardPanelAnimationScreen> createState() =>
      _StoryboardPanelAnimationScreenState();
}

class _StoryboardPanelAnimationScreenState
    extends State<StoryboardPanelAnimationScreen> {
  late final TextEditingController _prompt;
  late double _duration;
  bool _submitting = false;
  late final PromptEnhanceHost _enhancements = PromptEnhanceHost(
    fields: PromptEnhancementFields(
      repository: PromptEnhancementApiRepository(widget.controller.api),
      workspaceId: widget.controller.workspace!.id,
    ),
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  /// The rewrite affordance for the motion prompt.
  ///
  /// The panel image is the first frame, so this is an image-to-video prompt:
  /// the guide should be shaping what changes over time, not describing a
  /// picture that already exists.
  PromptEnhanceBinding? get _promptEnhanceBinding {
    final template = _template;
    if (template == null) return null;
    return _enhancements.binding(
      field: 'prompt',
      modality: 'video',
      workflowId: template.workflowId,
      targetModel: template.model,
      maxLength: template.inputs['prompt']?.maxLength ?? 8000,
      attachedImageCount: 1,
    );
  }

  WorkflowTemplateModel? get _template {
    final matches = widget.templates
        .where((template) => template.workflowId == 'image-to-video')
        .toList(growable: false);
    for (final template in matches) {
      if (template.enabled) return template;
    }
    return matches.isEmpty ? null : matches.first;
  }

  double get _minimumDuration =>
      _template?.inputs['duration_seconds']?.minimum ?? 2;
  double get _maximumDuration =>
      _template?.inputs['duration_seconds']?.maximum ?? 20;
  int get _durationDivisions =>
      (_maximumDuration.round() - _minimumDuration.round())
          .clamp(1, 1000)
          .toInt();

  double _clampDuration(num value) => value
      .roundToDouble()
      .clamp(_minimumDuration, _maximumDuration)
      .toDouble();

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: widget.panel.motionPrompt);
    _duration = _clampDuration(widget.panel.videoDurationSeconds);
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StoryboardPanelAnimationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_submitting &&
        (oldWidget.panel.id != widget.panel.id ||
            oldWidget.panel.videoJobId != widget.panel.videoJobId)) {
      _prompt.text = widget.panel.motionPrompt;
      _duration = _clampDuration(widget.panel.videoDurationSeconds);
    } else if (!_submitting) {
      _duration = _clampDuration(_duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final template = _template;
    final artifact = panel.imageArtifact;
    final canSubmit =
        widget.canEdit &&
        !_submitting &&
        !widget.loadingTemplates &&
        template?.enabled == true &&
        panel.imageJobId != null &&
        artifact != null &&
        _prompt.text.trim().isNotEmpty;
    return PageFrame(
      title: 'Animate panel ${widget.panelNumber}',
      subtitle:
          'The generated panel image is already attached. Describe only how the scene should move.',
      actions: [
        IconButton(
          tooltip: 'Back to storyboard',
          onPressed: _submitting ? null : widget.onBack,
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
        ),
        OutlinedButton.icon(
          onPressed: widget.onViewScenes,
          icon: const Icon(LucideIcons.clapperboard, size: 17),
          label: const Text('View scenes'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.loadingTemplates && template?.enabled != true) ...[
            _WorkflowUnavailable(template: template),
            IiOsGap.vMd,
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final source = _PanelSource(
                controller: widget.controller,
                panel: panel,
                panelNumber: widget.panelNumber,
              );
              final prompt = _MotionPrompt(
                controller: _prompt,
                duration: _duration,
                runtimeEstimate: template?.estimateRuntime({
                  'duration_seconds': _duration.round(),
                }),
                minimumDuration: _minimumDuration,
                maximumDuration: _maximumDuration,
                durationDivisions: _durationDivisions,
                enabled: widget.canEdit && !_submitting,
                submitting: _submitting,
                hasVideo: panel.videoArtifact != null,
                onChanged: () => setState(() {}),
                onDurationChanged: (value) => setState(() => _duration = value),
                onSubmit: canSubmit ? _submit : null,
                promptEnhance: _promptEnhanceBinding,
              );
              if (constraints.maxWidth < 840) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [source, IiOsGap.vMd, prompt],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: source),
                  IiOsGap.hMd,
                  Expanded(flex: 6, child: prompt),
                ],
              );
            },
          ),
          if (_submitting ||
              panel.videoJobId != null ||
              panel.videoGenerationError != null) ...[
            IiOsGap.vMd,
            if (_submitting)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(IiOsSpacing.md),
                  child: GeneratedMediaLoadingSurface(
                    kind: GeneratedMediaKind.video,
                    aspectRatio: 16 / 9,
                    label: 'Starting panel animation\u2026',
                  ),
                ),
              )
            else if (panel.videoJobId case final jobId?)
              JobSubmissionResult(
                key: ValueKey('storyboard-video-$jobId'),
                controller: widget.controller,
                result: {
                  ...?panel.videoJob,
                  'jobId': jobId,
                  'status': panel.videoStatus,
                },
                title: 'Panel animation',
                mediaKind: GeneratedMediaKind.video,
                mediaAspectRatio: 16 / 9,
              )
            else
              _AnimationFailure(panel: panel),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final template = _template;
    if (template == null) return;
    setState(() => _submitting = true);
    try {
      final response = await widget.controller.api.post(
        'v1/workspaces/${widget.controller.workspace!.id}/storyboards/'
        '${widget.storyboardId}/panels/${widget.panel.id}/animate',
        body: {
          'workflowKey': template.id,
          'input': {
            'prompt': _prompt.text.trim(),
            'duration_seconds': _duration.round(),
            'orientation': 'landscape',
            'fps': 24,
          },
        },
      );
      final data = asJsonMap(response['data']);
      widget.onStoryboardChanged(
        StoryboardModel.fromJson(asJsonMap(data['storyboard'])),
      );
      unawaited(widget.controller.refreshDashboard());
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _PanelSource extends StatelessWidget {
  const _PanelSource({
    required this.controller,
    required this.panel,
    required this.panelNumber,
  });

  final AppController controller;
  final StoryboardPanelDraft panel;
  final int panelNumber;

  @override
  Widget build(BuildContext context) {
    final artifact = panel.imageArtifact;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: artifact != null && panel.imageJobId != null
                ? StoryboardArtifactImage(
                    controller: controller,
                    workspaceId: controller.workspace!.id,
                    jobId: panel.imageJobId!,
                    artifact: artifact,
                  )
                : const ColoredBox(
                    color: IiOsColors.canvas,
                    child: Center(
                      child: Icon(
                        LucideIcons.imageOff,
                        color: IiOsColors.muted,
                        size: 30,
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(IiOsSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  'Panel $panelNumber source',
                  color: IiOsColors.green,
                ),
                const SizedBox(height: 10),
                Text(
                  panel.prompt.text.trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MotionPrompt extends StatelessWidget {
  const _MotionPrompt({
    required this.controller,
    required this.duration,
    required this.runtimeEstimate,
    required this.minimumDuration,
    required this.maximumDuration,
    required this.durationDivisions,
    required this.enabled,
    required this.submitting,
    required this.hasVideo,
    required this.onChanged,
    required this.onDurationChanged,
    required this.onSubmit,
    this.promptEnhance,
  });

  final TextEditingController controller;
  final double duration;
  final RuntimeEstimateSnapshot? runtimeEstimate;
  final double minimumDuration;
  final double maximumDuration;
  final int durationDivisions;
  final bool enabled;
  final bool submitting;
  final bool hasVideo;
  final VoidCallback onChanged;
  final ValueChanged<double> onDurationChanged;
  final VoidCallback? onSubmit;
  final PromptEnhanceBinding? promptEnhance;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('How should this scene move?'),
            IiOsGap.vSm,
            TextField(
              controller: controller,
              enabled: enabled,
              minLines: 10,
              maxLines: 16,
              maxLength: 8000,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Motion prompt',
                hintText:
                    'Describe subject movement, camera motion, timing, atmosphere, and sound\u2026',
                helperText:
                    'The panel image stays fixed as the starting frame. Focus on what changes over time.',
                alignLabelWithHint: true,
              ),
            ),
            if (promptEnhance case final binding?)
              PromptEnhanceBar(
                controller: controller,
                binding: binding,
                enabled: enabled,
              ),
            IiOsGap.vSm,
            DurationSelector(
              value: duration,
              minimum: minimumDuration,
              maximum: maximumDuration,
              divisions: durationDivisions,
              valueFormatter: (value) => '${value.round()} seconds',
              onChanged: enabled ? onDurationChanged : null,
            ),
            if (runtimeEstimate case final estimate?) ...[
              IiOsGap.vSm,
              RuntimeEstimateNotice(estimate: estimate),
            ],
            IiOsGap.vMd,
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onSubmit,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.play, size: 17),
                label: Text(hasVideo ? 'Generate again' : 'Animate panel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowUnavailable extends StatelessWidget {
  const _WorkflowUnavailable({required this.template});

  final WorkflowTemplateModel? template;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      decoration: BoxDecoration(
        color: IiOsColors.amberTint,
        border: Border.all(color: IiOsColors.amber),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circleAlert,
            size: 17,
            color: IiOsColors.amber,
          ),
          IiOsGap.hXs,
          Expanded(
            child: Text(
              template?.disabledReason.isNotEmpty == true
                  ? template!.disabledReason
                  : 'No enabled image-to-video workflow is available.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimationFailure extends StatelessWidget {
  const _AnimationFailure({required this.panel});

  final StoryboardPanelDraft panel;

  @override
  Widget build(BuildContext context) {
    final error =
        panel.videoGenerationError?['message']?.toString() ??
        panel.videoJobError?['message']?.toString() ??
        panel.videoJob?['errorCode']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Row(
          children: [
            Icon(LucideIcons.triangleAlert, color: IiOsColors.red),
            IiOsGap.hSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Animation could not be started',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IiOsGap.vXxs,
                  Text(
                    error ?? panel.videoJobId ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusPill(panel.videoStatus),
          ],
        ),
      ),
    );
  }
}
