import 'models.dart';

final class GenerationMetadataModel {
  const GenerationMetadataModel({
    required this.prompt,
    required this.model,
    required this.workflowKey,
  });

  factory GenerationMetadataModel.fromJob(JsonMap job) {
    final metadata = asJsonMap(job['generationMetadata']);
    final inputs = asJsonMap(job['inputs']);
    return GenerationMetadataModel(
      prompt: _firstText([metadata['prompt'], inputs['prompt']]),
      model: _firstText([
        metadata['model'],
        inputs['model'],
        job['workflowName'],
        job['kind'],
      ]),
      workflowKey: _firstText([
        metadata['workflowKey'],
        job['workflowKey'],
        job['kind'],
      ]),
    );
  }

  final String prompt;
  final String model;
  final String workflowKey;
}

final class HistoryEntryModel {
  const HistoryEntryModel({
    required this.jobId,
    required this.repository,
    required this.status,
    required this.submittedAt,
    required this.generation,
    required this.artifact,
    this.poster,
  });

  factory HistoryEntryModel.fromJobArtifact({
    required JsonMap job,
    required JsonMap artifact,
    JsonMap? poster,
  }) {
    return HistoryEntryModel(
      jobId: job['jobId']?.toString() ?? '',
      repository: job['repository']?.toString() ?? '',
      status: job['status']?.toString() ?? 'completed',
      submittedAt: DateTime.tryParse(
        job['submittedAt']?.toString() ?? job['createdAt']?.toString() ?? '',
      ),
      generation: GenerationMetadataModel.fromJob(job),
      artifact: artifact,
      poster: poster,
    );
  }

  final String jobId;
  final String repository;
  final String status;
  final DateTime? submittedAt;
  final GenerationMetadataModel generation;
  final JsonMap artifact;

  /// The image artifact that depicts this one, when the run reported one.
  ///
  /// A video cannot be shown in a grid without decoding it, so the workflow
  /// that produced it also uploads a frame. That frame is an ordinary
  /// artifact and is read through the same verified path as any other, which
  /// is why this is a whole artifact map rather than a URL.
  final JsonMap? poster;

  String get objectName => artifact['path']?.toString() ?? '';
  String get filename => objectName.split('/').last;
  String get generationId => artifact['generation']?.toString() ?? '';
  String get identity => '$jobId:$generationId:$objectName';
  bool get isImage => contentType.startsWith('image/');
  bool get isVideo => contentType.startsWith('video/');

  /// True when this artifact depicts another and should not be a card itself.
  bool get isPoster => artifact['role'] == 'poster';

  /// The artifact this one depicts, or empty when it depicts nothing.
  String get posterFor => artifact['poster_for']?.toString() ?? '';

  /// The artifact to draw on the card, or null when there is nothing to draw.
  ///
  /// An image depicts itself. A video depicts nothing until its run reports a
  /// poster, and audio never has a frame to show.
  JsonMap? get previewArtifact => isImage ? artifact : poster;
  bool get isAudio => contentType.startsWith('audio/');
  bool get isGeneratedMedia =>
      contentType.startsWith('image/') ||
      contentType.startsWith('video/') ||
      contentType.startsWith('audio/');

  String get contentType =>
      artifact['content_type']?.toString().trim().toLowerCase() ?? '';
}

String _firstText(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}
