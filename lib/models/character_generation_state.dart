import 'character.dart';

CharacterImageModel? characterImageForJob(
  Iterable<CharacterImageModel> images,
  String jobId,
) {
  for (final image in images) {
    if (image.jobId == jobId) return image;
  }
  return null;
}

List<CharacterImageModel> selectCharacterImageLocally(
  Iterable<CharacterImageModel> images,
  CharacterImageModel selected,
) => [
  for (final image in images)
    image.withSelected(
      image.jobId == selected.jobId &&
          image.path == selected.path &&
          image.generation == selected.generation,
    ),
];

String? pendingCharacterImageJobId({
  required String? jobId,
  required String? status,
  required Iterable<CharacterImageModel> images,
}) {
  final normalizedJobId = jobId?.trim() ?? '';
  if (normalizedJobId.isEmpty || !_activeStatuses.contains(status)) return null;
  return characterImageForJob(images, normalizedJobId) == null
      ? normalizedJobId
      : null;
}

bool isActiveCharacterGenerationStatus(String? status) =>
    _activeStatuses.contains(status);

bool shouldLoadCharacterImagesForGenerationStatus(String? status) =>
    status == 'completed';

const _activeStatuses = {
  'dispatching',
  'dispatched',
  'queued',
  'requested',
  'pending',
  'running',
  'in_progress',
  'cancelling',
};
