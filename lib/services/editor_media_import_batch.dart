import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

/// Imports one picker result as concurrent media at a captured timeline point.
///
/// [captureTimelineStart] is invoked exactly once before any source preparation
/// begins. Returning `false` rejects the current choice and stops the batch
/// before a later download, probe, or project mutation can begin.
Future<bool> runEditorMediaImportBatch<T>({
  required Iterable<T> choices,
  required MediaTime Function() captureTimelineStart,
  required Future<bool> Function(T choice, MediaTime timelineStart)
  importChoice,
}) async {
  final timelineStart = captureTimelineStart();
  for (final choice in choices) {
    if (!await importChoice(choice, timelineStart)) return false;
  }
  return true;
}
