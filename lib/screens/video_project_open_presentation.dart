import '../models/video_project.dart';
import '../services/editor_media_source.dart';
import '../view_models/video_editor_projects_view_model.dart';

/// Screen-owned media state that changes only after a project fully opens.
final class VideoProjectOpenPresentation {
  final Map<String, LocalEditorMedia> media = {};
  final Map<String, VideoProjectMediaOrigin> mediaOrigins = {};

  /// Replaces both media maps and the editor presentation as one accepted act.
  bool apply(
    VideoProjectOpenResult result, {
    required void Function(void Function()) refresh,
    required void Function() afterTimelineReplaced,
  }) {
    if (result is! VideoProjectOpened) return false;
    refresh(() {
      mediaOrigins
        ..clear()
        ..addEntries(
          result.project.media.map((item) => MapEntry(item.id, item.origin)),
        );
      media
        ..clear()
        ..addEntries(result.media.map((item) => MapEntry(item.id, item)));
    });
    afterTimelineReplaced();
    return true;
  }

  /// Clears presentation-owned state only after the ViewModel accepted it.
  bool clearIf(
    bool accepted, {
    required void Function(void Function()) refresh,
    required void Function() afterTimelineReplaced,
  }) {
    if (!accepted) return false;
    refresh(() {
      media.clear();
      mediaOrigins.clear();
    });
    afterTimelineReplaced();
    return true;
  }
}
