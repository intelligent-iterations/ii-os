import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../models/models.dart';
import '../models/storyboard.dart';
import '../services/client_error_reporter.dart';
import '../services/verified_artifact_media.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';
import 'storyboard_reference_selector.dart';
import 'verified_artifact_playback.dart';
import 'prompt_enhance_bar.dart';
import 'runtime_estimate_notice.dart';

class StoryboardPanelDraft {
  StoryboardPanelDraft({
    required this.id,
    required String prompt,
    required Set<String> characterIds,
    Set<String> referencePanelIds = const {},
    this.jobId,
    this.generationJobIds = const [],
    this.selectedImage,
    this.generationPrompt,
    this.job,
    this.jobError,
    this.selectedImageJob,
    this.selectedImageJobError,
    this.generationError,
    this.extendedFromPanelId,
    this.motionPrompt = '',
    this.videoDurationSeconds = 5,
    this.videoJobId,
    this.videoJob,
    this.videoJobError,
    this.videoGenerationError,
  }) : prompt = TextEditingController(text: prompt),
       characterIds = {...characterIds},
       referencePanelIds = {...referencePanelIds};

  factory StoryboardPanelDraft.fromModel(StoryboardPanelModel model) =>
      StoryboardPanelDraft(
        id: model.id,
        prompt: model.prompt,
        characterIds: model.characterIds,
        referencePanelIds: model.referencePanelIds,
        jobId: model.jobId,
        generationJobIds: model.generationJobIds,
        selectedImage: model.selectedImage,
        generationPrompt: model.generationPrompt,
        job: model.job,
        jobError: model.jobError,
        selectedImageJob: model.selectedImageJob,
        selectedImageJobError: model.selectedImageJobError,
        generationError: model.generationError,
        extendedFromPanelId: model.extendedFromPanelId,
        motionPrompt: model.motionPrompt,
        videoDurationSeconds: model.videoDurationSeconds,
        videoJobId: model.videoJobId,
        videoJob: model.videoJob,
        videoJobError: model.videoJobError,
        videoGenerationError: model.videoGenerationError,
      );

  final String id;
  final TextEditingController prompt;
  String motionPrompt;
  final Set<String> characterIds;
  final Set<String> referencePanelIds;
  String? jobId;
  List<String> generationJobIds;
  JsonMap? selectedImage;
  String? generationPrompt;
  JsonMap? job;
  JsonMap? jobError;
  JsonMap? selectedImageJob;
  JsonMap? selectedImageJobError;
  JsonMap? generationError;
  String? extendedFromPanelId;
  int videoDurationSeconds;
  String? videoJobId;
  JsonMap? videoJob;
  JsonMap? videoJobError;
  JsonMap? videoGenerationError;

  String? get promptSentToGenerator =>
      storyboardPromptSentToGenerator(job: imageTraceJob);

  JsonMap? get imageTraceJob {
    if (isActiveStoryboardJobStatus(status)) return job;
    final selectedJobId = selectedImage?['jobId'];
    if (selectedJobId is String &&
        selectedJobId.isNotEmpty &&
        selectedJobId != jobId) {
      return selectedImageJob;
    }
    return job;
  }

  String get status {
    final value = job?['status'] as String?;
    if (value != null && value.isNotEmpty) return value;
    if (generationError != null) return 'failed';
    return jobId == null ? 'draft' : 'dispatching';
  }

  JsonMap? get imageArtifact {
    if (isActiveStoryboardJobStatus(status) &&
        selectedImage?['jobId'] != jobId) {
      return null;
    }
    return storyboardImageArtifact(
      selectedImage: selectedImage,
      currentJobId: jobId,
      job: job,
      selectedImageJob: selectedImageJob,
    );
  }

  String? get imageJobId => isActiveStoryboardJobStatus(status)
      ? jobId
      : selectedImage?['jobId'] as String? ?? jobId;

  String get videoStatus {
    final value = videoJob?['status'] as String?;
    if (value != null && value.isNotEmpty) return value;
    if (videoGenerationError != null) return 'failed';
    return videoJobId == null ? 'draft' : 'dispatching';
  }

  JsonMap? get videoArtifact {
    for (final artifact
        in (videoJob?['artifacts'] as List<Object?>? ?? const [])) {
      final value = asJsonMap(artifact);
      if ((value['content_type'] as String? ?? '').startsWith('video/')) {
        return value;
      }
    }
    return null;
  }

  JsonMap toJson() => {
    'id': id,
    'prompt': prompt.text.trim(),
    'characterIds': characterIds.toList(),
    'referencePanelIds': referencePanelIds.toList(),
  };

  void mergeJob(StoryboardPanelModel model) {
    jobId = model.jobId;
    generationJobIds = model.generationJobIds;
    selectedImage = model.selectedImage;
    generationPrompt = model.generationPrompt;
    job = model.job;
    jobError = model.jobError;
    selectedImageJob = model.selectedImageJob;
    selectedImageJobError = model.selectedImageJobError;
    generationError = model.generationError;
    extendedFromPanelId = model.extendedFromPanelId;
    motionPrompt = model.motionPrompt;
    videoDurationSeconds = model.videoDurationSeconds;
    videoJobId = model.videoJobId;
    videoJob = model.videoJob;
    videoJobError = model.videoJobError;
    videoGenerationError = model.videoGenerationError;
  }

  void dispose() {
    prompt.dispose();
  }
}

class StoryboardOverviewField extends StatelessWidget {
  const StoryboardOverviewField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.promptEnhance,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  /// Offers to rewrite the overview against the guide for the panel model.
  final PromptEnhanceBinding? promptEnhance;

  @override
  Widget build(BuildContext context) {
    final words = storyboardWordCount(controller.text);
    final overLimit = words > storyboardOverviewWordLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Story overview'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              enabled: enabled,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Brief, rich description of the whole story',
                helperText:
                    'Maximum 150 words so the complete story stays concise and useful for every scene.',
                alignLabelWithHint: true,
              ),
            ),
            if (promptEnhance case final binding?)
              PromptEnhanceBar(
                controller: controller,
                binding: binding,
                enabled: enabled,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$words/$storyboardOverviewWordLimit words',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: overLimit ? IiOsColors.red : IiOsColors.muted,
                  fontWeight: overLimit ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoryboardPanelCountBar extends StatelessWidget {
  const StoryboardPanelCountBar({
    required this.count,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final int count;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$count panels',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const StatusPill('min 3'),
              const StatusPill('max 9'),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove panel',
          onPressed: onRemove,
          icon: const Icon(LucideIcons.minus, size: 18),
        ),
        IconButton(
          tooltip: 'Add panel',
          onPressed: onAdd,
          icon: const Icon(LucideIcons.plus, size: 18),
        ),
      ],
    );
  }
}

class StoryboardArtifactImage extends StatefulWidget {
  const StoryboardArtifactImage({
    required this.controller,
    required this.workspaceId,
    required this.jobId,
    required this.artifact,
    super.key,
  });

  final AppController controller;
  final String workspaceId;
  final String jobId;
  final JsonMap artifact;

  @override
  State<StoryboardArtifactImage> createState() =>
      _StoryboardArtifactImageState();
}

class _StoryboardArtifactImageState extends State<StoryboardArtifactImage> {
  late Future<VerifiedArtifactMedia> _media;

  @override
  void initState() {
    super.initState();
    _media = _load();
  }

  @override
  void didUpdateWidget(StoryboardArtifactImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.artifact['path'] != widget.artifact['path'] ||
        oldWidget.artifact['generation'] != widget.artifact['generation']) {
      _media = _load();
    }
  }

  Future<VerifiedArtifactMedia> _load() async {
    try {
      return await widget.controller.readVerifiedArtifact(
        workspaceId: widget.workspaceId,
        jobId: widget.jobId,
        artifact: widget.artifact,
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        ClientErrorReporter.reportGlobal(
          error,
          stackTrace,
          source: 'storyboard.artifact.verified',
          workspaceId: widget.workspaceId,
        ),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VerifiedArtifactMedia>(
      future: _media,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(
            child: Icon(LucideIcons.imageOff, color: IiOsColors.muted),
          );
        }
        return VerifiedArtifactImage(media: snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}

class StoryboardPanelEditor extends StatelessWidget {
  const StoryboardPanelEditor({
    this.controller,
    required this.panel,
    required this.panelNumber,
    required this.characters,
    required this.panelReferences,
    required this.loadingCharacters,
    required this.enabled,
    required this.generating,
    required this.canGenerate,
    required this.onChanged,
    required this.onGenerate,
    this.imagePicker,
    this.extendPicker,
    this.workflowNotice,
    this.runtimeEstimate,
    this.promptEnhance,
    super.key,
  });

  final StoryboardPanelDraft panel;
  final AppController? controller;
  final int panelNumber;
  final List<CharacterModel> characters;
  final List<StoryboardPanelReferenceOption> panelReferences;
  final bool loadingCharacters;
  final bool enabled;
  final bool generating;
  final bool canGenerate;
  final VoidCallback onChanged;
  final VoidCallback onGenerate;
  final Widget? imagePicker;
  final Widget? extendPicker;
  final Widget? workflowNotice;
  final RuntimeEstimateSnapshot? runtimeEstimate;

  /// Offers to rewrite this panel's prompt under the storyboard continuity
  /// rules, so the cast stays recognisable from one panel to the next.
  final PromptEnhanceBinding? promptEnhance;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'Panel $panelNumber',
              trailing: StatusPill(panel.status),
            ),
            if (imagePicker != null) ...[IiOsGap.vSm, imagePicker!],
            if (extendPicker != null) ...[IiOsGap.vSm, extendPicker!],
            IiOsGap.vSm,
            TextField(
              controller: panel.prompt,
              enabled: enabled && !generating,
              minLines: 5,
              maxLines: 10,
              maxLength: 4000,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Scene prompt',
                helperText:
                    'Describe this image. Selected character and panel images are sent as visual references.',
                alignLabelWithHint: true,
              ),
            ),
            if (promptEnhance case final binding?)
              PromptEnhanceBar(
                controller: panel.prompt,
                binding: binding,
                enabled: enabled && !generating,
              ),
            IiOsGap.vSm,
            StoryboardReferenceSelector(
              controller: controller,
              characters: characters,
              panels: panelReferences,
              selectedCharacterIds: panel.characterIds,
              selectedPanelIds: panel.referencePanelIds,
              loadingCharacters: loadingCharacters,
              enabled: enabled && !generating,
              onChanged: onChanged,
            ),
            if (panel.jobId != null) ...[IiOsGap.vMd, _JobTrace(panel: panel)],
            if (workflowNotice != null) ...[IiOsGap.vMd, workflowNotice!],
            if (runtimeEstimate case final estimate?) ...[
              IiOsGap.vMd,
              RuntimeEstimateNotice(estimate: estimate),
            ],
            IiOsGap.vMd,
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: !canGenerate || generating ? null : onGenerate,
                icon: generating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.wandSparkles, size: 17),
                label: const Text('Generate panel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTrace extends StatelessWidget {
  const _JobTrace({required this.panel});

  final StoryboardPanelDraft panel;

  @override
  Widget build(BuildContext context) {
    final promptSentToGenerator = panel.imageArtifact == null
        ? null
        : panel.promptSentToGenerator;
    String? selectedImageError;
    if (panel.imageJobId != panel.jobId) {
      selectedImageError = panel.selectedImageJobError?['message']?.toString();
    }
    final error =
        selectedImageError ??
        panel.generationError?['message']?.toString() ??
        panel.jobError?['message']?.toString() ??
        panel.job?['errorCode']?.toString();
    return Material(
      color: IiOsColors.canvas,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: IiOsColors.border),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Job ${panel.imageJobId ?? panel.jobId}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                error,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: IiOsColors.red),
              ),
            ],
            if (promptSentToGenerator != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: IiOsSpacing.xxs),
                title: const Text('Prompt sent to generator'),
                subtitle: const Text('Final prompt after prompt enhancement'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      promptSentToGenerator,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Widget? storyboardWorkflowNotice({
  required BuildContext context,
  required bool loadingTemplates,
  required bool usesReference,
  required WorkflowTemplateModel? template,
}) {
  if (loadingTemplates) {
    return const WorkflowPendingNotice(message: 'Loading image workflows.');
  }
  if (template?.enabled == true) return null;
  final reason = template?.disabledReason.isNotEmpty == true
      ? template!.disabledReason
      : usesReference
      ? 'No image-edit workflow is configured for storyboard references.'
      : 'No image generation workflow is configured.';
  if (reason.toLowerCase().startsWith('waiting for')) {
    return WorkflowPendingNotice(message: reason);
  }
  return Container(
    padding: const EdgeInsets.all(IiOsSpacing.sm),
    decoration: BoxDecoration(
      color: IiOsColors.amberTint,
      border: Border.all(color: IiOsColors.amber),
      borderRadius: BorderRadius.circular(IiOsRadii.md),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.circleAlert, size: 17, color: IiOsColors.amber),
        IiOsGap.hXs,
        Expanded(
          child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
