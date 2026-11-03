import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../models/song_generation_options.dart';
import '../models/song_render_profile.dart';
import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../widgets/prompt_enhance_bar.dart';
import 'prompt_enhancement_support.dart';

abstract final class SongGenerationBusy {
  static const templates = 'templates';
  static const submit = 'submit';
}

const double minimumSongDurationSeconds = 10;

final class SongGenerationViewModel extends BaseViewModel
    with PromptEnhancementSupport {
  SongGenerationViewModel({
    required this._templates,
    required this._jobs,
    required this.promptEnhancements,
    required this.workspaceId,
    this.ghostMode = false,
    this._onSubmitted,
  });

  final WorkflowTemplateRepository _templates;
  final JobRepository _jobs;
  final Future<void> Function()? _onSubmitted;

  @override
  final PromptEnhancementRepository promptEnhancements;

  @override
  final String workspaceId;

  bool ghostMode;
  List<WorkflowTemplateModel> templates = const [];
  String? selectedTemplateId;
  String generationProfileId = defaultSongRenderProfile.id;
  double durationSeconds = defaultSongRenderProfile.maxDurationSeconds;
  bool instrumental = false;
  String vocalLanguage = 'unknown';
  String keyScale = '';
  String timeSignature = '';
  JsonMap? submittedJob;

  bool get loadingTemplates => busy(SongGenerationBusy.templates);
  bool get submitting => busy(SongGenerationBusy.submit);
  WorkflowTemplateModel? get selectedTemplate =>
      resolveSelectedTemplate(templates, selectedId: selectedTemplateId);
  RuntimeEstimateSnapshot? get runtimeEstimate =>
      selectedTemplate?.estimateRuntime({
        'generation_profile': generationProfile.id,
        'duration_seconds': durationSeconds.round(),
      });
  SongRenderProfile get generationProfile =>
      songRenderProfileById(generationProfileId);
  bool get canSubmit =>
      !loadingTemplates && !submitting && selectedTemplate?.enabled == true;
  bool get showsUnavailableNotice =>
      !loadingTemplates && selectedTemplate?.enabled != true;
  int get durationDivisions =>
      ((generationProfile.maxDurationSeconds - minimumSongDurationSeconds) / 10)
          .round();

  PromptEnhanceBinding? get descriptionBinding => enhanceBindingFor(
    field: 'prompt',
    workflowId: selectedTemplate?.workflowId,
    targetModel: selectedTemplate?.model,
    modality: 'music',
    maxLength: selectedTemplate?.inputs['prompt']?.maxLength ?? 4000,
  );

  PromptEnhanceBinding? get lyricsBinding => enhanceBindingFor(
    field: 'lyrics',
    workflowId: selectedTemplate?.workflowId,
    targetModel: selectedTemplate?.model,
    modality: 'lyrics',
    maxLength: selectedTemplate?.inputs['lyrics']?.maxLength ?? 30000,
  );

  Future<void> load() async {
    setBusyForObject(SongGenerationBusy.templates, true);
    try {
      templates = await _templates.list(
        workspaceId,
        workflowIdPrefix: 'song-create',
      );
      setError(null);
    } on Object catch (error) {
      setError(error);
    } finally {
      setBusyForObject(SongGenerationBusy.templates, false);
    }
  }

  void setGhostMode(bool value) => ghostMode = value;

  void selectTemplate(String? value) {
    selectedTemplateId = value;
    submittedJob = null;
    notifyListeners();
  }

  void selectGenerationProfile(String value) {
    final profile = songRenderProfileById(value);
    generationProfileId = profile.id;
    durationSeconds = durationSeconds
        .clamp(minimumSongDurationSeconds, profile.maxDurationSeconds)
        .toDouble();
    submittedJob = null;
    notifyListeners();
  }

  void setDuration(double value) {
    durationSeconds = value
        .roundToDouble()
        .clamp(minimumSongDurationSeconds, generationProfile.maxDurationSeconds)
        .toDouble();
    submittedJob = null;
    notifyListeners();
  }

  void setInstrumental(bool value) {
    instrumental = value;
    submittedJob = null;
    notifyListeners();
  }

  void setVocalLanguage(String value) {
    if (!isSupportedSongLanguage(value)) return;
    vocalLanguage = value;
    submittedJob = null;
    notifyListeners();
  }

  void setKeyScale(String value) {
    if (!songKeyScales.contains(value)) return;
    keyScale = value;
    submittedJob = null;
    notifyListeners();
  }

  void setTimeSignature(String value) {
    if (!songTimeSignatures.any((option) => option.value == value)) return;
    timeSignature = value;
    submittedJob = null;
    notifyListeners();
  }

  Future<JsonMap?> submit({
    required String prompt,
    required String lyrics,
    required String bpm,
    required String seed,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      setError(const FormatException('A song description is required.'));
      return null;
    }
    final parsedBpm = _optionalInt(bpm);
    if (bpm.trim().isNotEmpty &&
        (parsedBpm == null || parsedBpm < 30 || parsedBpm > 300)) {
      setError(const FormatException('BPM must be between 30 and 300.'));
      return null;
    }
    final parsedSeed = _optionalInt(seed);
    if (seed.trim().isNotEmpty && parsedSeed == null) {
      setError(const FormatException('Seed must be a number.'));
      return null;
    }
    final template = selectedTemplate;
    if (template == null || !template.enabled) {
      setError(
        const FormatException(
          'No enabled song-generation workflow is available.',
        ),
      );
      return null;
    }

    submittedJob = null;
    setBusyForObject(SongGenerationBusy.submit, true);
    setError(null);
    try {
      submittedJob = await _jobs.submit(
        workspaceId,
        JobSubmission(
          workflowKey: template.id,
          pageSlug: 'songs',
          ghostMode: ghostMode,
          keptEnhancedText: keptEnhancedTextFor('prompt'),
          input: {
            'prompt': trimmedPrompt,
            'lyrics': instrumental ? '' : lyrics.trim(),
            'instrumental': instrumental,
            'duration_seconds': durationSeconds.round(),
            'generation_profile': generationProfile.id,
            'bpm': ?parsedBpm,
            'key_scale': keyScale,
            'time_signature': timeSignature,
            'vocal_language': instrumental ? 'unknown' : vocalLanguage,
            'seed': ?parsedSeed,
          },
        ),
      );
      await _onSubmitted?.call();
      return submittedJob;
    } on Object catch (error) {
      setError(error);
      return null;
    } finally {
      setBusyForObject(SongGenerationBusy.submit, false);
    }
  }
}

int? _optionalInt(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : int.tryParse(normalized);
}
