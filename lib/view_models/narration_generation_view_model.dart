import 'dart:typed_data';

import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../repositories/workflow_template_repository.dart';
import 'prompt_enhancement_support.dart';

abstract final class NarrationGenerationBusy {
  static const templates = 'templates';
  static const submit = 'submit';
}

typedef VoiceReferenceUpload =
    Future<String> Function({
      required String workspaceId,
      required String expectedBucket,
      required String filename,
      required Uint8List bytes,
      required String contentType,
      required bool ghostMode,
    });

final class NarrationGenerationViewModel extends BaseViewModel
    with PromptEnhancementSupport {
  NarrationGenerationViewModel({
    required WorkflowTemplateRepository templates,
    required JobRepository jobs,
    required PromptEnhancementRepository promptEnhancements,
    required String workspaceId,
    VoiceReferenceUpload? voiceReferenceUploader,
    String expectedBucket = '',
    bool ghostMode = false,
    Future<void> Function()? onSubmitted,
  }) : this._(
         templates: templates,
         jobs: jobs,
         promptEnhancements: promptEnhancements,
         workspaceId: workspaceId,
         voiceReferenceUploader: voiceReferenceUploader,
         expectedBucket: expectedBucket,
         ghostMode: ghostMode,
         onSubmitted: onSubmitted,
       );

  NarrationGenerationViewModel._({
    required this._templates,
    required this._jobs,
    required this.promptEnhancements,
    required this.workspaceId,
    required this._voiceReferenceUploader,
    required this._expectedBucket,
    required this.ghostMode,
    this._onSubmitted,
  });

  final WorkflowTemplateRepository _templates;
  final JobRepository _jobs;

  @override
  final PromptEnhancementRepository promptEnhancements;

  final VoiceReferenceUpload? _voiceReferenceUploader;
  final String _expectedBucket;
  bool ghostMode;

  void setGhostMode(bool value) => ghostMode = value;
  final Future<void> Function()? _onSubmitted;

  @override
  final String workspaceId;

  List<WorkflowTemplateModel> templates = const [];
  String? selectedTemplateId;
  JsonMap? submittedJob;

  bool get loadingTemplates => busy(NarrationGenerationBusy.templates);

  bool get submitting => busy(NarrationGenerationBusy.submit);

  WorkflowTemplateModel? get selectedTemplate =>
      resolveSelectedTemplate(templates, selectedId: selectedTemplateId);

  RuntimeEstimateSnapshot? get runtimeEstimate =>
      selectedTemplate?.estimateRuntime(const {});

  bool get canSubmit =>
      !submitting && !loadingTemplates && selectedTemplate?.enabled == true;

  bool get showsUnavailableNotice =>
      !loadingTemplates && selectedTemplate?.enabled != true;

  Future<void> load() async {
    setBusyForObject(NarrationGenerationBusy.templates, true);
    try {
      templates = await _templates.list(
        workspaceId,
        workflowIdPrefix: 'narration-create',
      );
      setError(null);
    } on Object catch (error) {
      setError(error);
    } finally {
      setBusyForObject(NarrationGenerationBusy.templates, false);
    }
  }

  void selectTemplate(String? id) {
    selectedTemplateId = id;
    notifyListeners();
  }

  Future<String> uploadVoiceReference({
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) {
    final uploader = _voiceReferenceUploader;
    if (uploader == null || _expectedBucket.isEmpty) {
      throw StateError('Workspace source asset upload is not configured.');
    }
    return uploader(
      workspaceId: workspaceId,
      expectedBucket: _expectedBucket,
      filename: filename,
      bytes: bytes,
      contentType: contentType,
      ghostMode: ghostMode,
    );
  }

  /// The rewrite affordance for the narration script.
  ///
  /// This is the field the old resolver got most wrong: it went to an image
  /// guide, which rewrote a script as a description of a picture and dropped
  /// its negations on the way. Naming the modality keeps that impossible even
  /// if a workflow is renamed.
  PromptEnhanceBinding? get narrationBinding => enhanceBindingFor(
    field: 'text',
    modality: 'speech',
    workflowId: selectedTemplate?.workflowId,
    targetModel: selectedTemplate?.model,
    maxLength: selectedTemplate?.inputs['text']?.maxLength ?? 6000,
  );

  Future<JsonMap?> submit({
    required String text,
    required String voiceModel,
    required String language,
    required String seed,
    String? voiceReferenceAssetId,
    bool voiceCloneConsent = false,
  }) async {
    final input = _validatedInput(
      text: text,
      voiceModel: voiceModel,
      language: language,
      seed: seed,
      voiceReferenceAssetId: voiceReferenceAssetId,
      voiceCloneConsent: voiceCloneConsent,
    );
    if (input == null) return null;
    final template = selectedTemplate;
    if (template == null || !template.enabled) {
      setError(
        const FormatException('No enabled narration workflow is available.'),
      );
      return null;
    }
    return _submitJob(template.id, input);
  }

  JsonMap? _validatedInput({
    required String text,
    required String voiceModel,
    required String language,
    required String seed,
    String? voiceReferenceAssetId,
    required bool voiceCloneConsent,
  }) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      setError(const FormatException('Narration text is required.'));
      return null;
    }
    if (trimmedText.length > 6000) {
      setError(
        const FormatException(
          'Narration text must be 6,000 characters or less.',
        ),
      );
      return null;
    }
    final normalizedVoiceModel = voiceModel.trim().isEmpty
        ? 'chatterbox-turbo'
        : voiceModel.trim();
    if (!narrationVoiceModels.contains(normalizedVoiceModel)) {
      setError(
        const FormatException('Selected narration voice is unavailable.'),
      );
      return null;
    }
    final normalizedLanguage = language.trim().isEmpty
        ? 'English'
        : language.trim();
    if (normalizedLanguage.length > 32) {
      setError(
        const FormatException('Language must be 32 characters or less.'),
      );
      return null;
    }
    final trimmedSeed = seed.trim();
    final parsedSeed = trimmedSeed.isEmpty ? null : int.tryParse(trimmedSeed);
    if (trimmedSeed.isNotEmpty && parsedSeed == null) {
      setError(const FormatException('Seed must be a number.'));
      return null;
    }
    final voiceReference = _validatedVoiceReference(
      voiceReferenceAssetId,
      consent: voiceCloneConsent,
    );
    if (!voiceReference.valid) return null;
    return {
      'text': trimmedText,
      'voice_model': normalizedVoiceModel,
      'language': normalizedLanguage,
      'seed': ?parsedSeed,
      if (voiceReference.assetId.isNotEmpty) ...{
        'voice_reference_asset_id': voiceReference.assetId,
        'voice_clone_consent': true,
      },
    };
  }

  ({bool valid, String assetId}) _validatedVoiceReference(
    String? assetId, {
    required bool consent,
  }) {
    final normalized = assetId?.trim() ?? '';
    if (consent && normalized.isEmpty) {
      setError(
        const FormatException('A voice reference audio file is required.'),
      );
      return (valid: false, assetId: normalized);
    }
    if (normalized.isNotEmpty && !_validSourceAssetId(normalized)) {
      setError(const FormatException('The voice reference asset is invalid.'));
      return (valid: false, assetId: normalized);
    }
    if (normalized.isNotEmpty && !consent) {
      setError(
        const FormatException(
          'Voice cloning requires confirming you have permission to use the reference voice.',
        ),
      );
      return (valid: false, assetId: normalized);
    }
    return (valid: true, assetId: normalized);
  }

  Future<JsonMap?> _submitJob(String workflowKey, JsonMap input) async {
    submittedJob = null;
    setBusyForObject(NarrationGenerationBusy.submit, true);
    setError(null);
    try {
      submittedJob = await _jobs.submit(
        workspaceId,
        JobSubmission(
          keptEnhancedText: keptEnhancedTextFor('text'),
          workflowKey: workflowKey,
          pageSlug: 'narration',
          ghostMode: ghostMode,
          input: input,
        ),
      );
      await _onSubmitted?.call();
      return submittedJob;
    } on Object catch (error) {
      setError(error);
      return null;
    } finally {
      setBusyForObject(NarrationGenerationBusy.submit, false);
    }
  }
}

const narrationVoiceModels = {'chatterbox-turbo'};

bool _validSourceAssetId(String value) => RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-'
  r'[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
).hasMatch(value);
