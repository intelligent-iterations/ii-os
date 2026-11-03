part of 'video_generation_view_model.dart';

extension MiniMaxH3LibraryReferences on VideoGenerationViewModel {
  bool get addingH3LibraryReference =>
      busy(VideoGenerationBusy.libraryReference);

  GenerationHistoryRepository get h3ReferenceHistory =>
      _media.history(workspaceId: workspaceId, retentionDays: 30);

  /// Fetches bytes for any reference that arrived as an id alone, so the
  /// editor can show it. The video-editor handoff creates such a draft.
  ///
  /// Preview is not worth failing the page for: a reference that cannot be
  /// fetched keeps its media-kind icon.
  Future<void> _hydrateH3ReferenceBytes() async {
    for (var index = 0; index < h3References.length; index++) {
      final reference = h3References[index];
      final assetId = reference.assetId;
      if (reference.bytes.isNotEmpty || assetId == null) continue;
      try {
        final media = await _media.readVerifiedSourceAsset(
          workspaceId: workspaceId,
          assetId: assetId,
          expectedBucket: expectedBucket,
        );
        if (index < h3References.length &&
            h3References[index].id == reference.id) {
          h3References[index] = reference.copyWith(bytes: media.bytes);
          notifyListeners();
        }
      } on Object {
        continue;
      }
    }
  }

  Future<bool> addGeneratedH3Reference({
    required MiniMaxH3ReferenceKind kind,
    required HistoryEntryModel entry,
  }) async {
    if (!entry.contentType.startsWith('${kind.name}/')) {
      setError(
        FormatException(
          'Choose a generated ${kind.name} from the Asset Library.',
        ),
      );
      return false;
    }
    setBusyForObject(VideoGenerationBusy.libraryReference, true);
    setError(null);
    try {
      final media = await _media.readVerifiedArtifact(
        workspaceId: workspaceId,
        jobId: entry.jobId,
        expectedBucket: expectedBucket,
        artifact: entry.artifact,
      );
      return addH3Reference(
        kind: kind,
        filename: entry.filename,
        bytes: media.bytes,
      );
    } on Object catch (error) {
      setError(error);
      return false;
    } finally {
      setBusyForObject(VideoGenerationBusy.libraryReference, false);
    }
  }
}
