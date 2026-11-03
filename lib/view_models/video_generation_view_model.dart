import 'dart:typed_data';

import 'package:stacked/stacked.dart';

import '../models/generation_history.dart';
import '../models/models.dart';
import '../models/minimax_h3_generation_spec.dart';
import '../repositories/generation_history_repository.dart';
import '../repositories/job_repository.dart';
import '../repositories/media_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../services/verified_artifact_media.dart';
import '../repositories/source_asset_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../services/source_asset_uploader.dart';
import 'prompt_enhancement_support.dart';

part 'video_generation_continuation_view_model.dart';
part 'video_generation_h3_view_model.dart';
part 'video_generation_prompt_view_model.dart';
part 'video_generation_library_view_model.dart';
part 'video_generation_submission_view_model.dart';

abstract final class VideoGenerationBusy {
  static const templates = 'templates';
  static const submit = 'submit';
  static const libraryReference = 'library-reference';
}

const String minimaxH3WorkflowId = 'text-to-video-minimax-h3';
const String ltxImageToVideoWorkflowId = 'image-to-video';
const String seedVr2VideoUpscaleWorkflowId = 'seedvr2-video-upscale';

final class VideoGenerationViewModel extends BaseViewModel
    with PromptEnhancementSupport {
  VideoGenerationViewModel({
    required this._templates,
    required this._jobs,
    required this._sourceAssets,
    required this._media,
    required this.promptEnhancements,
    required this.workspaceId,
    required this.expectedBucket,
    this.ghostMode = false,
    this.initialH3Mode,
    this.initialH3SourceAssetId,
    this._onSubmitted,
  });

  final WorkflowTemplateRepository _templates;
  final JobRepository _jobs;
  final SourceAssetRepository _sourceAssets;
  final WorkspaceMediaRepository _media;

  @override
  final PromptEnhancementRepository promptEnhancements;

  final Future<void> Function()? _onSubmitted;
  final MiniMaxH3GenerationMode? initialH3Mode;
  final String? initialH3SourceAssetId;

  @override
  final String workspaceId;

  final String expectedBucket;
  bool ghostMode;

  void setGhostMode(bool value) {
    if (ghostMode == value) return;
    ghostMode = value;
    sourceAssetId = null;
    for (var index = 0; index < h3References.length; index++) {
      h3References[index] = h3References[index].copyWith(clearAssetId: true);
    }
  }

  List<WorkflowTemplateModel> templates = const [];
  String? selectedTemplateId;
  JsonMap? submittedJob;
  Uint8List? sourceBytes;
  String? sourceFilename;
  String? sourceContentType;
  String? sourceAssetId;
  String orientation = 'landscape';
  int fps = 24;
  double duration = 5;
  String busyLabel = 'Launch job';
  MiniMaxH3GenerationMode h3Mode = MiniMaxH3GenerationMode.textToVideo;
  MiniMaxH3PerformanceMode h3PerformanceMode = MiniMaxH3PerformanceMode.quality;
  MiniMaxH3EditOperation h3EditOperation = MiniMaxH3EditOperation.general;
  MiniMaxH3ExtensionMethod h3ExtensionMethod =
      MiniMaxH3ExtensionMethod.singlePass;
  bool identityReplacementConsent = false;
  final List<MiniMaxH3ReferenceDraft> h3References = [];
  int _referenceSequence = 0;
  JobSubmission? _lastSubmission;
  final Map<String, double> _durationByTemplate = {};

  bool get loadingTemplates => busy(VideoGenerationBusy.templates);
  bool get submitting => busy(VideoGenerationBusy.submit);

  WorkflowTemplateModel? get selectedTemplate =>
      resolveSelectedTemplate(templates, selectedId: selectedTemplateId);

  bool get isMiniMaxH3 => selectedTemplate?.workflowId == minimaxH3WorkflowId;
  bool get isSeedVr2 =>
      selectedTemplate?.workflowId == seedVr2VideoUpscaleWorkflowId;

  bool get sourceImageRequired => !isMiniMaxH3 && !isSeedVr2;
  bool get sourceVideoRequired => isSeedVr2;
  bool get canSubmit =>
      !submitting && !loadingTemplates && selectedTemplate?.enabled == true;
  bool get showsUnavailableNotice =>
      !loadingTemplates && selectedTemplate?.enabled != true;
  String get resolution =>
      orientation == 'landscape' ? '1280 × 720' : '720 × 1280';
  double get outputAspectRatio => orientation == 'portrait' ? 9 / 16 : 16 / 9;
  WorkflowInputModel? get durationInput =>
      selectedTemplate?.inputs['duration_seconds'];
  RuntimeEstimateSnapshot? get runtimeEstimate =>
      selectedTemplate?.estimateRuntime({
        'duration_seconds': duration.round(),
        if (isMiniMaxH3)
          minimaxH3PerformanceModeInput: h3PerformanceMode.wireValue,
      });
  double get minimumDuration {
    final published =
        (durationInput?.minimum ??
                (isMiniMaxH3
                    ? MiniMaxH3GenerationSpec.minimumDurationSeconds
                    : 2))
            .toDouble();
    return isMiniMaxH3
        ? published
              .clamp(
                MiniMaxH3GenerationSpec.minimumDurationSeconds,
                MiniMaxH3GenerationSpec.maximumDurationSeconds,
              )
              .toDouble()
        : published;
  }

  double get maximumDuration {
    final published =
        (durationInput?.maximum ??
                (isMiniMaxH3
                    ? MiniMaxH3GenerationSpec.maximumDurationSeconds
                    : 20))
            .toDouble();
    return isMiniMaxH3
        ? published
              .clamp(
                MiniMaxH3GenerationSpec.minimumDurationSeconds,
                MiniMaxH3GenerationSpec.maximumDurationSeconds,
              )
              .toDouble()
        : published;
  }

  int get durationDivisions =>
      (maximumDuration.round() - minimumDuration.round())
          .clamp(1, 1000)
          .toInt();

  Future<void> load() async {
    setBusyForObject(VideoGenerationBusy.templates, true);
    try {
      final all = await _templates.list(workspaceId);
      templates = all
          .where(
            (template) =>
                template.workflowId == ltxImageToVideoWorkflowId ||
                template.workflowId == minimaxH3WorkflowId ||
                template.workflowId == seedVr2VideoUpscaleWorkflowId,
          )
          .toList(growable: false);
      _applyInitialH3Selection();
      _applySelectedContract();
      await _hydrateH3ReferenceBytes();
      setError(null);
    } on Object catch (error) {
      setError(error);
    } finally {
      setBusyForObject(VideoGenerationBusy.templates, false);
    }
  }

  void selectTemplate(String? id) {
    final current = selectedTemplate;
    if (current != null) _durationByTemplate[current.id] = duration;
    selectedTemplateId = id;
    submittedJob = null;
    h3Mode = MiniMaxH3GenerationMode.textToVideo;
    h3PerformanceMode = MiniMaxH3PerformanceMode.quality;
    h3References.clear();
    identityReplacementConsent = false;
    sourceBytes = null;
    sourceFilename = null;
    sourceContentType = null;
    sourceAssetId = null;
    _applySelectedContract();
    notifyListeners();
  }

  void setOrientation(String value) {
    if (value != 'landscape' && value != 'portrait') return;
    orientation = value;
    submittedJob = null;
    notifyListeners();
  }

  void setFps(int value) {
    if (isMiniMaxH3) return;
    fps = value;
    submittedJob = null;
    notifyListeners();
  }

  void setDuration(double value) {
    duration = value
        .roundToDouble()
        .clamp(minimumDuration, maximumDuration)
        .toDouble();
    final template = selectedTemplate;
    if (template != null) _durationByTemplate[template.id] = duration;
    submittedJob = null;
    notifyListeners();
  }

  bool setSource({required String filename, required Uint8List bytes}) {
    final contentType = sourceImageContentType(bytes);
    if (bytes.isEmpty ||
        bytes.length > 50 * 1024 * 1024 ||
        contentType == null) {
      setError(
        const FormatException('Select a JPEG, PNG, or WebP image under 50 MB.'),
      );
      return false;
    }
    sourceFilename = filename;
    sourceBytes = bytes;
    sourceContentType = contentType;
    sourceAssetId = null;
    submittedJob = null;
    setError(null);
    notifyListeners();
    return true;
  }

  bool setSourceVideo({required String filename, required Uint8List bytes}) {
    final contentType = sourceVideoContentType(bytes, filename: filename);
    final lowerFilename = filename.toLowerCase();
    final supportedContainer =
        (contentType == 'video/mp4' && lowerFilename.endsWith('.mp4')) ||
        (contentType == 'video/webm' && lowerFilename.endsWith('.webm'));
    if (bytes.isEmpty ||
        bytes.length > 512 * 1024 * 1024 ||
        !supportedContainer) {
      setError(
        const FormatException(
          'Select an MP4 or WebM source video under 512 MB.',
        ),
      );
      return false;
    }
    sourceFilename = filename;
    sourceBytes = bytes;
    sourceContentType = contentType;
    sourceAssetId = null;
    submittedJob = null;
    setError(null);
    notifyListeners();
    return true;
  }

  void _applySelectedContract() {
    final template = selectedTemplate;
    if (template == null) return;
    if (isMiniMaxH3 || isSeedVr2) {
      orientation = 'portrait';
      fps = 24;
    }
    final fallback = isMiniMaxH3 ? 15.0 : 5.0;
    duration =
        (_durationByTemplate[template.id] ??
                durationInput?.defaultNumber ??
                fallback)
            .roundToDouble()
            .clamp(minimumDuration, maximumDuration)
            .toDouble();
    _durationByTemplate[template.id] = duration;
  }

  void _applyInitialH3Selection() {
    final mode = initialH3Mode;
    final assetId = initialH3SourceAssetId;
    if (mode == null || assetId == null || assetId.isEmpty) return;
    final template = templates
        .where((item) => item.workflowId == minimaxH3WorkflowId)
        .firstOrNull;
    if (template == null) return;
    selectedTemplateId = template.id;
    if (!supportsH3ReferenceInputs || !h3ModeEnabled(mode)) return;
    h3Mode = mode;
    addUploadedH3Reference(
      kind: MiniMaxH3ReferenceKind.video,
      role: MiniMaxH3ReferenceRole.sourceVideo,
      filename: 'video-editor-output.mp4',
      contentType: 'video/mp4',
      assetId: assetId,
    );
  }

  int? _validatedDurationSeconds() {
    final seconds = duration.round();
    if (seconds >= minimumDuration && seconds <= maximumDuration) {
      return seconds;
    }
    setError(
      FormatException(
        'Video duration must be between '
        '${minimumDuration.round()} and ${maximumDuration.round()} seconds.',
      ),
    );
    return null;
  }

  /// Reads the preview bytes for one asset-library entry.
  ///
  /// The picker takes a loader rather than a repository, so this is where the
  /// workspace and its expected bucket are bound.
  Future<VerifiedArtifactMedia> readLibraryPreview(HistoryEntryModel entry) =>
      _media.readVerifiedArtifact(
        workspaceId: workspaceId,
        jobId: entry.jobId,
        expectedBucket: expectedBucket,
        artifact: entry.previewArtifact ?? entry.artifact,
      );

  Future<String> _uploadSource() async {
    final assetId = await _sourceAssets.upload(
      workspaceId: workspaceId,
      expectedBucket: expectedBucket,
      filename: sourceFilename!,
      bytes: sourceBytes!,
      contentType: sourceContentType!,
      ghostMode: ghostMode,
    );
    sourceAssetId = assetId;
    return assetId;
  }
}
