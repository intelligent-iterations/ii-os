import 'models.dart';

const storyboardOverviewWordLimit = 150;
const storyboardMinimumPanels = 3;
const storyboardMaximumPanels = 9;

final class StoryboardModel {
  const StoryboardModel({
    required this.id,
    required this.name,
    required this.overview,
    required this.panels,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoryboardModel.fromJson(JsonMap json) => StoryboardModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Untitled storyboard',
    overview: json['overview'] as String? ?? '',
    panels: (json['panels'] as List<Object?>? ?? const [])
        .map(asJsonMap)
        .map(StoryboardPanelModel.fromJson)
        .toList(),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  final String id;
  final String name;
  final String overview;
  final List<StoryboardPanelModel> panels;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

final class StoryboardPanelModel {
  const StoryboardPanelModel({
    required this.id,
    required this.prompt,
    required this.characterIds,
    this.referencePanelIds = const {},
    required this.jobId,
    required this.generationJobIds,
    required this.selectedImage,
    required this.generationPrompt,
    required this.job,
    required this.jobError,
    required this.selectedImageJob,
    required this.selectedImageJobError,
    required this.generationError,
    this.extendedFromPanelId,
    required this.motionPrompt,
    required this.videoDurationSeconds,
    required this.videoJobId,
    required this.videoJob,
    required this.videoJobError,
    required this.videoGenerationError,
  });

  factory StoryboardPanelModel.fromJson(JsonMap json) => StoryboardPanelModel(
    id: json['id'] as String? ?? '',
    prompt: json['prompt'] as String? ?? '',
    characterIds: (json['characterIds'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet(),
    referencePanelIds: (json['referencePanelIds'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet(),
    jobId: json['jobId'] as String?,
    generationJobIds: _panelGenerationJobIds(json),
    selectedImage: json['selectedImage'] == null
        ? null
        : asJsonMap(json['selectedImage']),
    generationPrompt: json['generationPrompt'] as String?,
    job: json['job'] == null ? null : asJsonMap(json['job']),
    jobError: json['jobError'] == null ? null : asJsonMap(json['jobError']),
    selectedImageJob: json['selectedImageJob'] == null
        ? null
        : asJsonMap(json['selectedImageJob']),
    selectedImageJobError: json['selectedImageJobError'] == null
        ? null
        : asJsonMap(json['selectedImageJobError']),
    generationError: json['generationError'] == null
        ? null
        : asJsonMap(json['generationError']),
    extendedFromPanelId: json['extendedFromPanelId'] as String?,
    motionPrompt: json['videoGenerationPrompt'] as String? ?? '',
    videoDurationSeconds: (json['videoDurationSeconds'] as num?)?.toInt() ?? 5,
    videoJobId: json['videoJobId'] as String?,
    videoJob: json['videoJob'] == null ? null : asJsonMap(json['videoJob']),
    videoJobError: json['videoJobError'] == null
        ? null
        : asJsonMap(json['videoJobError']),
    videoGenerationError: json['videoGenerationError'] == null
        ? null
        : asJsonMap(json['videoGenerationError']),
  );

  final String id;
  final String prompt;
  final Set<String> characterIds;
  final Set<String> referencePanelIds;
  final String? jobId;
  final List<String> generationJobIds;
  final JsonMap? selectedImage;
  final String? generationPrompt;
  final JsonMap? job;
  final JsonMap? jobError;
  final JsonMap? selectedImageJob;
  final JsonMap? selectedImageJobError;
  final JsonMap? generationError;
  final String? extendedFromPanelId;
  final String motionPrompt;
  final int videoDurationSeconds;
  final String? videoJobId;
  final JsonMap? videoJob;
  final JsonMap? videoJobError;
  final JsonMap? videoGenerationError;

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
}

bool isActiveStoryboardJobStatus(String? status) => const {
  'dispatching',
  'dispatched',
  'queued',
  'requested',
  'running',
  'in_progress',
  'pending',
  'cancelling',
}.contains(status);

JsonMap? storyboardImageArtifact({
  required JsonMap? selectedImage,
  required String? currentJobId,
  required JsonMap? job,
  required JsonMap? selectedImageJob,
}) {
  final selected = selectedImage;
  if (selected == null) return _firstStoryboardImageArtifact(job);
  final selectedJobId = selected['jobId']?.toString() ?? '';
  final metadataJob = selectedJobId.isNotEmpty && selectedJobId != currentJobId
      ? selectedImageJob
      : job;
  final selectedPath = selected['path']?.toString() ?? '';
  final selectedGeneration = selected['generation']?.toString() ?? '';
  for (final artifact
      in (metadataJob?['artifacts'] as List<Object?>? ?? const [])) {
    final candidate = asJsonMap(artifact);
    if (candidate['path']?.toString() != selectedPath ||
        candidate['generation']?.toString() != selectedGeneration) {
      continue;
    }
    final merged = <String, Object?>{...candidate, ...selected};
    for (final key in const [
      'path',
      'generation',
      'size_bytes',
      'sha256',
      'content_type',
    ]) {
      final selectedValue = selected[key];
      if (selectedValue == null || selectedValue.toString().trim().isEmpty) {
        merged[key] = candidate[key];
      }
    }
    final legacyContentType = selected['contentType']?.toString() ?? '';
    if ((merged['content_type']?.toString() ?? '').isEmpty &&
        legacyContentType.isNotEmpty) {
      merged['content_type'] = legacyContentType;
    }
    return merged;
  }
  if ((selected['content_type']?.toString() ?? '').isNotEmpty ||
      (selected['contentType']?.toString() ?? '').isEmpty) {
    return selected;
  }
  return {...selected, 'content_type': selected['contentType']};
}

JsonMap? _firstStoryboardImageArtifact(JsonMap? job) {
  for (final artifact in (job?['artifacts'] as List<Object?>? ?? const [])) {
    final value = asJsonMap(artifact);
    if ((value['content_type'] as String? ?? '').startsWith('image/')) {
      return value;
    }
  }
  return null;
}

String? storyboardPromptSentToGenerator({required JsonMap? job}) {
  final generationMetadata = asJsonMap(job?['generationMetadata']);
  final inputs = asJsonMap(job?['inputs']);
  for (final value in [inputs['prompt'], generationMetadata['prompt']]) {
    final prompt = value?.toString().trim() ?? '';
    if (prompt.isNotEmpty) return prompt;
  }
  return null;
}

final class StoryboardPanelImageModel {
  const StoryboardPanelImageModel({
    required this.jobId,
    required this.path,
    required this.generation,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.selected,
    required this.createdAt,
  });

  factory StoryboardPanelImageModel.fromJson(JsonMap json) =>
      StoryboardPanelImageModel(
        jobId: json['jobId'] as String? ?? '',
        path: json['path'] as String? ?? '',
        generation: json['generation'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
        selected: json['selected'] == true,
        createdAt: _date(json['createdAt']),
      );

  final String jobId;
  final String path;
  final String generation;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final bool selected;
  final DateTime? createdAt;

  String get filename => path.split('/').last;

  JsonMap get artifact => {
    'path': path,
    'generation': generation,
    'content_type': contentType,
    'size_bytes': sizeBytes,
    'sha256': sha256,
  };
}

int storyboardWordCount(String value) =>
    RegExp(r'\S+').allMatches(value.trim()).length;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

List<String> _panelGenerationJobIds(JsonMap json) {
  final ids = (json['generationJobIds'] as List<Object?>? ?? const [])
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList();
  final latest = json['jobId'];
  if (latest is String && latest.isNotEmpty && !ids.contains(latest)) {
    ids.add(latest);
  }
  return ids;
}
