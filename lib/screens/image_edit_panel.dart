import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        GenerationPhase,
        GenerationSlot,
        GenerationWorkspace,
        GhostModeControl,
        IiOsMotion;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/creative_presets.dart';
import '../models/picked_media.dart';
import '../models/image_edit_selection.dart';
import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../repositories/source_asset_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../state/prompt_enhance_host.dart';
import '../state/prompt_enhancement_fields.dart';
import '../services/image_dimensions.dart';
import '../services/picked_media_reader.dart';
import '../services/source_asset_uploader.dart' show sourceImageContentType;
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import '../widgets/image_edit_controls.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../widgets/image_edit_model_picker.dart';
import '../widgets/image_edit_submission_results.dart';
import '../widgets/media_picker.dart';
import '../widgets/runtime_estimate_notice.dart';
import '../widgets/source_image_field.dart';
import '../view_models/image_edit_submission_view_model.dart';

part 'image_edit_sources.dart';
part 'image_edit_form.dart';
part 'image_edit_preview_pane.dart';

final class ImageEditScreen extends StatefulWidget {
  const ImageEditScreen({
    required this.controller,
    this.initialMode = ImageEditMode.revision,
    this.initialTemplateId,
    this.onModeChanged,
    this.onTemplateChanged,
    this.ghostMode = false,
    this.onGhostModeChanged,
    this.templateRepository,
    super.key,
  });

  final AppController controller;
  final ImageEditMode initialMode;
  final String? initialTemplateId;
  final ValueChanged<ImageEditMode>? onModeChanged;
  final ValueChanged<String?>? onTemplateChanged;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;
  final WorkflowTemplateRepository? templateRepository;

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<ImageEditScreen> {
  final _prompt = TextEditingController();
  final _seed = TextEditingController();
  late final PromptEnhanceHost _enhancements = PromptEnhanceHost(
    fields: PromptEnhancementFields(
      repository: PromptEnhancementApiRepository(widget.controller.api),
      workspaceId: widget.controller.workspace!.id,
    ),
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  List<WorkflowTemplateModel> _templates = const [];
  late ImageEditMode _mode;
  XFile? _sourceFile;
  Uint8List? _sourceBytes;
  String? _sourceContentType, _sourceAssetId;
  final List<XFile?> _referenceFiles = List<XFile?>.filled(2, null);
  final List<Uint8List?> _referenceBytes = List<Uint8List?>.filled(2, null);
  final List<String?> _referenceContentTypes = List<String?>.filled(2, null);
  final List<String?> _referenceAssetIds = List<String?>.filled(2, null);
  double _imageAspectRatio = 1;
  double _controlStrength = sourceAdherenceDefault;
  List<Rect> _maskRegions = const [];
  bool _loadingTemplates = true;
  bool _busy = false;
  String _busyLabel = 'Launch job';
  late String? _selectedTemplateId;
  bool _useAll = false;
  List<ImageEditSubmission> _submissions = const [];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _selectedTemplateId = widget.initialTemplateId;
    _loadTemplates();
  }

  @override
  void didUpdateWidget(covariant ImageEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ghostMode != widget.ghostMode) {
      _sourceAssetId = null;
      for (var index = 0; index < _referenceAssetIds.length; index++) {
        _referenceAssetIds[index] = null;
      }
    }
    if (oldWidget.initialMode != widget.initialMode ||
        oldWidget.initialTemplateId != widget.initialTemplateId) {
      final hasValidTemplate =
          widget.initialTemplateId == null ||
          _loadingTemplates ||
          _templates.any(
            (template) =>
                template.id == widget.initialTemplateId &&
                template.enabled &&
                isImageEditWorkflowForMode(
                  template.workflowId,
                  widget.initialMode,
                ),
          );
      setState(() {
        _mode = widget.initialMode;
        _selectedTemplateId = hasValidTemplate
            ? widget.initialTemplateId
            : null;
      });
      if (!hasValidTemplate) _clearInvalidTemplateUrl();
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _seed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final template = _selectedTemplate;
    final modeTemplates = imageEditTemplatesForMode(_templates, _mode);
    final enabledTemplates = enabledImageEditTemplates(_templates, _mode);
    final targets = imageEditSubmissionTargets(
      templates: _templates,
      mode: _mode,
      selectedId: _selectedTemplateId,
      useAll: _useAll,
    );
    final referenceSlots = maximumImageEditReferenceSlots(targets);
    final showsSourceAdherence =
        !_useAll &&
        template != null &&
        imageEditSupportsSourceAdherence(template);
    return _ImageEditPage(
      controller: widget.controller,
      ghostMode: widget.ghostMode,
      onGhostModeChanged: widget.onGhostModeChanged,
      showUnavailable: !_loadingTemplates && template?.enabled != true,
      unavailableMessage: template?.disabledReason.isNotEmpty == true
          ? template!.disabledReason
          : 'No enabled workflow is available for this edit mode.',
      data: _ImageEditUiState(
        mode: _mode,
        modeTemplates: modeTemplates,
        enabledTemplates: enabledTemplates,
        selectedTemplate: template,
        runtimeEstimate: imageEditRuntimeEstimate(targets),
        referenceSlots: referenceSlots,
        showsSourceAdherence: showsSourceAdherence,
        sourceFile: _sourceFile,
        sourceBytes: _sourceBytes,
        referenceFiles: _referenceFiles,
        referenceBytes: _referenceBytes,
        imageAspectRatio: _imageAspectRatio,
        maskRegions: _maskRegions,
        prompt: _prompt,
        seed: _seed,
        promptEnhance: _promptEnhanceBinding,
        controlStrength: _controlStrength,
        useAll: _useAll,
        busy: _busy,
        loadingTemplates: _loadingTemplates,
        busyLabel: _busyLabel,
        onModeChanged: _selectMode,
        onTemplateChanged: _selectTemplate,
        onUseAllChanged: (value) => setState(() {
          _useAll = value;
          _submissions = const [];
        }),
        onSelectSource: () => _selectImage(),
        onSelectReference: (index) => _selectImage(referenceIndex: index),
        onClearReference: _clearReference,
        onMasksChanged: (value) => setState(() => _maskRegions = value),
        onClearMasks: () => setState(() => _maskRegions = const []),
        onControlStrengthChanged: (value) =>
            setState(() => _controlStrength = value),
        onSubmit: _submit,
      ),
      submissions: _submissions,
    );
  }

  PromptEnhanceBinding? get _promptEnhanceBinding {
    final template = _selectedTemplate;
    if (template == null) return null;
    return _enhancements.binding(
      field: 'prompt',
      workflowId: template.workflowId,
      targetModel: template.model,
      modality: _mode == ImageEditMode.inpaint ? 'inpaint' : 'image_edit',
      maxLength: template.inputs['prompt']?.maxLength ?? 4000,
      attachedImageCount: _attachedImageCount,
    );
  }

  int get _attachedImageCount =>
      (_sourceAssetId == null && _sourceBytes == null ? 0 : 1) +
      _referenceBytes
          .take(
            maximumImageEditReferenceSlots(
              imageEditSubmissionTargets(
                templates: _templates,
                mode: _mode,
                selectedId: _selectedTemplateId,
                useAll: _useAll,
              ),
            ),
          )
          .where((bytes) => bytes != null)
          .length;

  WorkflowTemplateModel? get _selectedTemplate => selectedImageEditTemplate(
    templates: _templates,
    mode: _mode,
    selectedId: _selectedTemplateId,
  );

  void _selectMode(ImageEditMode mode) {
    setState(() {
      _mode = mode;
      _selectedTemplateId = null;
      _useAll = false;
      _submissions = const [];
    });
    widget.onModeChanged?.call(mode);
  }

  void _selectTemplate(String? value) {
    setState(() {
      _selectedTemplateId = value;
      _submissions = const [];
    });
    widget.onTemplateChanged?.call(value);
  }

  Future<void> _loadTemplates() async {
    try {
      final workspaceId = widget.controller.workspace!.id;
      final loaded =
          await (widget.templateRepository ??
                  WorkflowTemplateApiRepository(widget.controller.api))
              .list(workspaceId, workflowIdPrefix: 'image-');
      final templates = loaded
          .where(
            (item) =>
                isImageEditWorkflowForMode(
                  item.workflowId,
                  ImageEditMode.revision,
                ) ||
                isImageEditWorkflowForMode(
                  item.workflowId,
                  ImageEditMode.inpaint,
                ),
          )
          .toList();
      if (mounted) {
        final hasValidTemplate =
            _selectedTemplateId == null ||
            templates.any(
              (template) =>
                  template.id == _selectedTemplateId &&
                  template.enabled &&
                  isImageEditWorkflowForMode(template.workflowId, _mode),
            );
        setState(() {
          _templates = templates;
          _loadingTemplates = false;
          if (!hasValidTemplate) _selectedTemplateId = null;
        });
        if (!hasValidTemplate) _clearInvalidTemplateUrl();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _loadingTemplates = false);
        showFailure(context, error);
      }
    }
  }

  void _clearInvalidTemplateUrl() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTemplateChanged?.call(null);
    });
  }

  Future<void> _selectImage({int? referenceIndex}) async {
    const images = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final controller = widget.controller;
    final workspace = controller.workspace;
    if (workspace == null) return;
    final picked = await showMediaPicker(
      context: context,
      history: controller.media.history(
        workspaceId: workspace.id,
        retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
      ),
      title: referenceIndex == null
          ? 'Choose the picture to change'
          : 'Choose image ${String.fromCharCode(66 + referenceIndex)}',
      contentTypePrefix: 'image/',
      uploadTypes: const [images],
      maxUploadBytes: _maxImageBytes,
      loadPreview: (entry) => controller.readVerifiedArtifact(
        workspaceId: workspace.id,
        jobId: entry.jobId,
        artifact: entry.previewArtifact ?? entry.artifact,
      ),
    );
    if (picked == null || !mounted) return;
    await _readIntoField(picked, referenceIndex: referenceIndex);
  }

  /// Reads a chosen picture and puts it in the field that asked for it.
  ///
  /// Reading a library choice is a download from the workspace bucket, so the
  /// form has to say it is working; without this the screen simply sits there
  /// after the sheet closes.
  Future<void> _readIntoField(
    PickedMedia picked, {
    required int? referenceIndex,
  }) async {
    final controller = widget.controller;
    final workspaceId = controller.workspace!.id;
    setState(() {
      _busy = true;
      _busyLabel = 'Reading image';
    });
    try {
      final selected = await readPickedMedia(
        picked,
        readLibrary: (entry) => controller.readVerifiedArtifact(
          workspaceId: workspaceId,
          jobId: entry.jobId,
          artifact: entry.artifact,
        ),
      );
      final bytes = selected.bytes;
      final contentType = sourceImageContentType(bytes);
      if (bytes.isEmpty ||
          bytes.length > _maxImageBytes ||
          contentType == null) {
        throw const FormatException(
          'Choose a JPEG, PNG, or WebP image under 50 MB.',
        );
      }
      final aspectRatio = await decodeImageAspectRatio(bytes);
      if (!mounted) return;
      setState(() {
        if (referenceIndex == null) {
          _sourceFile = selected.file;
          _sourceBytes = bytes;
          _sourceContentType = contentType;
          _sourceAssetId = null;
          _imageAspectRatio = aspectRatio;
          _maskRegions = const [];
        } else {
          _referenceFiles[referenceIndex] = selected.file;
          _referenceBytes[referenceIndex] = bytes;
          _referenceContentTypes[referenceIndex] = contentType;
          _referenceAssetIds[referenceIndex] = null;
        }
        _submissions = const [];
      });
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = 'Launch job';
        });
      }
    }
  }

  void _clearReference(int index) {
    setState(() {
      _referenceFiles[index] = null;
      _referenceBytes[index] = null;
      _referenceContentTypes[index] = null;
      _referenceAssetIds[index] = null;
      _submissions = const [];
    });
  }

  Future<void> _submit() async {
    final targets = imageEditSubmissionTargets(
      templates: _templates,
      mode: _mode,
      selectedId: _selectedTemplateId,
      useAll: _useAll,
    );
    setState(() {
      _busy = true;
      _busyLabel = 'Preparing edit';
      _submissions = const [];
    });
    try {
      final outcome =
          await ImageEditSubmissionViewModel(
            JobApiRepository(widget.controller.api),
            SourceAssetApiRepository(widget.controller.api),
          ).submit(
            ImageEditSubmissionRequest(
              workspaceId: widget.controller.workspace!.id,
              expectedBucket: widget.controller.connection?.bucket ?? '',
              mode: _mode,
              targets: targets,
              prompt: _prompt.text,
              seedText: _seed.text,
              sourceFilename: _sourceFile?.name,
              sourceBytes: _sourceBytes,
              sourceContentType: _sourceContentType,
              sourceAssetId: _sourceAssetId,
              referenceFilenames: _referenceFiles
                  .map((file) => file?.name)
                  .toList(),
              referenceBytes: _referenceBytes,
              referenceContentTypes: _referenceContentTypes,
              referenceAssetIds: _referenceAssetIds,
              maskRegions: _maskRegions,
              controlStrength: _controlStrength,
              ghostMode: widget.ghostMode,
              keptEnhancedText: _enhancements.fields.keptEnhancedTextFor(
                'prompt',
              ),
            ),
            onPhase: (label) {
              if (mounted) setState(() => _busyLabel = label);
            },
          );
      if (!mounted) return;
      setState(() {
        _sourceAssetId = outcome.sourceAssetId;
        for (var index = 0; index < _referenceAssetIds.length; index++) {
          _referenceAssetIds[index] = outcome.referenceAssetIds[index];
        }
        if (_seed.text.trim().isEmpty && outcome.effectiveSeed != null) {
          _seed.text = '${outcome.effectiveSeed}';
        }
        _submissions = outcome.submissions;
      });
      if (outcome.submissions.any((item) => item.succeeded)) {
        await widget.controller.refreshDashboard();
      }
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = 'Launch job';
        });
      }
    }
  }
}

const _maxImageBytes = 50 * 1024 * 1024;
