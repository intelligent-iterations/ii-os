import 'models.dart';

enum GeneratedMediaKind { image, video, audio }

JsonMap? generatedMediaArtifact(JsonMap job, GeneratedMediaKind kind) {
  final prefix = switch (kind) {
    GeneratedMediaKind.image => 'image/',
    GeneratedMediaKind.video => 'video/',
    GeneratedMediaKind.audio => 'audio/',
  };
  for (final raw in (job['artifacts'] as List<Object?>? ?? const [])) {
    final artifact = asJsonMap(raw);
    if ((artifact['content_type'] as String? ?? '').startsWith(prefix) &&
        (artifact['path'] as String? ?? '').isNotEmpty) {
      return artifact;
    }
  }
  return null;
}

bool generatedMediaJobIsActive(String status) => const {
  'dispatching',
  'dispatched',
  'queued',
  'requested',
  'running',
  'in_progress',
  'pending',
  'cancelling',
}.contains(status);
