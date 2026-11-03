import 'dart:typed_data';

import 'package:stacked/stacked.dart';

import '../models/image_workflow_capabilities.dart';
import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../repositories/source_asset_repository.dart';
import '../services/source_asset_uploader.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../repositories/workflow_template_repository.dart';
import 'prompt_enhancement_support.dart';

/// Busy keys, so the template load and the job submission can be distinguished
/// by the view instead of sharing one boolean.
abstract final class ImageGenerationBusy {
  static const templates = 'templates';
  static const submit = 'submit';
}

/// State for the image generation page.
///
/// Everything the old `_GenerateScreenState` held except the text controllers,
/// which belong to the widgets that own them. Constructor-injected so a unit
/// test can drive it with fake repositories and no widget tree.
final class ImageGenerationViewModel extends BaseViewModel
    with PromptEnhancementSupport {
  /// Callers pass `templates:`, `jobs:`, and `onSubmitted:` -- private named
  /// parameters keep the fields private without a redundant initializer list.
  ImageGenerationViewModel({
    required this._templates,
    required this._jobs,
    required this._sourceAssets,
    required this.promptEnhancements,
    required this.workspaceId,
    required this.expectedBucket,
    this.ghostMode = false,
    ImageGenerationMode initialMode = ImageGenerationMode.prompt,
    String? initialTemplateId,
    this._onSubmitted,
  }) : mode = initialMode,
       selectedTemplateId = initialTemplateId;

  final WorkflowTemplateRepository _templates;
  final JobRepository _jobs;
  final SourceAssetRepository _sourceAssets;

  @override
  final PromptEnhancementRepository promptEnhancements;

  final Future<void> Function()? _onSubmitted;

  @override
  final String workspaceId;
  final String expectedBucket;

  bool ghostMode;

  void setGhostMode(bool value) {
    if (ghostMode == value) return;
    ghostMode = value;
    for (var index = 0; index < references.length; index++) {
      final reference = references[index];
      if (reference != null) references[index] = reference.withoutAssetId();
    }
  }

  List<WorkflowTemplateModel> _allTemplates = const [];
  ImageGenerationMode mode;
  String? selectedTemplateId;
  JsonMap? submittedJob;
  String busyLabel = 'Launch job';
  final List<ImageReferenceDraft?> references = List.filled(3, null);

  List<WorkflowTemplateModel> get templates =>
      imageGenerationTemplatesForMode(_allTemplates, mode);

  bool get loadingTemplates => busy(ImageGenerationBusy.templates);

  bool get submitting => busy(ImageGenerationBusy.submit);

  WorkflowTemplateModel? get selectedTemplate =>
      resolveSelectedTemplate(templates, selectedId: selectedTemplateId);

  RuntimeEstimateSnapshot? get runtimeEstimate =>
      selectedTemplate?.estimateRuntime(const {});

  ImageWorkflowCapabilities? get capabilities => switch (selectedTemplate) {
    final template? => imageCapabilities(template),
    _ => null,
  };

  int get maximumReferenceImages =>
      (capabilities?.maximumReferenceImages ?? 0).clamp(0, references.length);

  List<String> get aspectRatios => capabilities?.aspectRatios ?? const [];

  bool get canSubmit =>
      !submitting &&
      !loadingTemplates &&
      selectedTemplate?.enabled == true &&
      (mode == ImageGenerationMode.prompt || references.first != null);

  /// True once a load has finished and left nothing runnable, which is when the
  /// view should explain why rather than show a disabled button.
  bool get showsUnavailableNotice =>
      !loadingTemplates && selectedTemplate?.enabled != true;

  Future<void> load() async {
    setBusyForObject(ImageGenerationBusy.templates, true);
    try {
      _allTemplates = await _templates.list(
        workspaceId,
        workflowIdPrefix: 'image-create',
      );
      if (!templates.any((item) => item.id == selectedTemplateId)) {
        selectedTemplateId = null;
      }
      setError(null);
    } on Object catch (error) {
      setError(error);
    } finally {
      setBusyForObject(ImageGenerationBusy.templates, false);
    }
  }

  void selectTemplate(String? id) {
    selectedTemplateId = id;
    submittedJob = null;
    notifyListeners();
  }

  void setMode(ImageGenerationMode value) {
    if (mode == value) return;
    mode = value;
    selectedTemplateId = null;
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  bool setReference(
    int index, {
    required String filename,
    required Uint8List bytes,
  }) {
    if (index < 0 || index >= maximumReferenceImages) return false;
    final contentType = sourceImageContentType(bytes);
    if (bytes.isEmpty ||
        bytes.length > _maximumImageBytes ||
        contentType == null) {
      setError(
        const FormatException('Choose a JPEG, PNG, or WebP image under 50 MB.'),
      );
      return false;
    }
    references[index] = ImageReferenceDraft(
      filename: filename,
      bytes: bytes,
      contentType: contentType,
    );
    submittedJob = null;
    setError(null);
    notifyListeners();
    return true;
  }

  void removeReference(int index) {
    if (index < 0 || index >= references.length) return;
    references.removeAt(index);
    references.add(null);
    submittedJob = null;
    notifyListeners();
  }

  /// Submits a job. Returns the created job, or null when validation or the
  /// request failed -- in which case [modelError] carries the reason.
  /// The rewrite affordance for the image prompt.
  PromptEnhanceBinding? get promptBinding => enhanceBindingFor(
    field: 'prompt',
    workflowId: selectedTemplate?.workflowId,
    targetModel: selectedTemplate?.model,
    maxLength: selectedTemplate?.inputs['prompt']?.maxLength ?? 4000,
  );

  Future<JsonMap?> submit({
    required String prompt,
    required String aspectRatio,
    required String seed,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      setError(const FormatException('A prompt is required.'));
      return null;
    }
    final trimmedSeed = seed.trim();
    final parsedSeed = trimmedSeed.isEmpty ? null : int.tryParse(trimmedSeed);
    if (trimmedSeed.isNotEmpty && parsedSeed == null) {
      setError(const FormatException('Seed must be a number.'));
      return null;
    }
    final template = selectedTemplate;
    if (template == null || !template.enabled) {
      setError(
        const FormatException('No enabled image workflow is available.'),
      );
      return null;
    }
    final ratioInput = template.inputs['aspect_ratio'];
    if (ratioInput != null &&
        ratioInput.allowedValues.isNotEmpty &&
        !ratioInput.allowedValues.contains(aspectRatio)) {
      setError(const FormatException('Choose an available image shape.'));
      return null;
    }
    if (mode == ImageGenerationMode.references && references.first == null) {
      setError(
        const FormatException('Add image A before generating from references.'),
      );
      return null;
    }

    submittedJob = null;
    busyLabel = mode == ImageGenerationMode.references
        ? 'Uploading references'
        : 'Launching job';
    setBusyForObject(ImageGenerationBusy.submit, true);
    setError(null);
    try {
      final model = template.inputs.containsKey('model')
          ? imageModelInput(template.workflowId)
          : null;
      final input = <String, Object?>{
        if (template.inputs.containsKey('prompt')) 'prompt': trimmedPrompt,
        if (template.inputs.containsKey('aspect_ratio'))
          'aspect_ratio': aspectRatio,
        if (template.inputs.containsKey('model')) 'model': ?model,
        if (template.inputs.containsKey('seed')) 'seed': ?parsedSeed,
        if (template.inputs.containsKey('mode')) 'mode': 'edit',
      };
      if (mode == ImageGenerationMode.references) {
        final assetIds = await _uploadReferences();
        for (var index = 0; index < assetIds.length; index++) {
          final name = index == 0
              ? 'source_asset_id'
              : 'source_asset_id_${index + 1}';
          if (template.inputs.containsKey(name)) input[name] = assetIds[index];
        }
        busyLabel = 'Launching job';
        notifyListeners();
      }
      submittedJob = await _jobs.submit(
        workspaceId,
        JobSubmission(
          workflowKey: template.id,
          pageSlug: 'images',
          ghostMode: ghostMode,
          keptEnhancedText: keptEnhancedText,
          input: input,
        ),
      );
      await _onSubmitted?.call();
      return submittedJob;
    } on Object catch (error) {
      setError(error);
      return null;
    } finally {
      busyLabel = 'Launch job';
      setBusyForObject(ImageGenerationBusy.submit, false);
    }
  }

  Future<List<String>> _uploadReferences() async {
    final selected = references.take(maximumReferenceImages).toList();
    final last = selected.lastIndexWhere((item) => item != null);
    if (last < 0 || selected.take(last + 1).any((item) => item == null)) {
      throw const FormatException(
        'Add reference images in order, starting with image A.',
      );
    }
    final uploads = await Future.wait([
      for (var index = 0; index <= last; index++)
        _uploadReference(index, selected[index]!),
    ]);
    return uploads;
  }

  Future<String> _uploadReference(
    int index,
    ImageReferenceDraft reference,
  ) async {
    final existing = reference.assetId;
    if (existing != null) return existing;
    final assetId = await _sourceAssets.upload(
      workspaceId: workspaceId,
      filename: reference.filename,
      bytes: reference.bytes,
      contentType: reference.contentType,
      expectedBucket: expectedBucket,
      ghostMode: ghostMode,
    );
    references[index] = reference.withAssetId(assetId);
    return assetId;
  }
}

final class ImageReferenceDraft {
  const ImageReferenceDraft({
    required this.filename,
    required this.bytes,
    required this.contentType,
    this.assetId,
  });

  final String filename;
  final Uint8List bytes;
  final String contentType;
  final String? assetId;

  ImageReferenceDraft withAssetId(String value) => ImageReferenceDraft(
    filename: filename,
    bytes: bytes,
    contentType: contentType,
    assetId: value,
  );

  ImageReferenceDraft withoutAssetId() => ImageReferenceDraft(
    filename: filename,
    bytes: bytes,
    contentType: contentType,
  );
}

/// Workflows that take an explicit `model` input.
String? imageModelInput(String workflowId) => switch (workflowId) {
  'image-create' => 'z-image-turbo',
  'image-create-flux2-klein' => 'flux2-klein',
  'image-create-qwen-2512' => 'qwen-image-2512',
  _ => null,
};

const _maximumImageBytes = 50 * 1024 * 1024;
