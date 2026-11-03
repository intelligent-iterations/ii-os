import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

EditorProject feasibilityProject(
  List<EditorLane> lanes, {
  MediaOutputSettings output = const MediaOutputSettings(),
}) => EditorProject(
  id: 'feasibility-project',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(60),
  lanes: lanes,
  output: output,
);

EditorLane feasibilityVideoLane(
  String id,
  MediaSource source, {
  int count = 1,
  List<MediaSource>? sources,
  bool hidden = false,
}) {
  final actualSources = sources ?? List.filled(count, source);
  return EditorLane(
    id: '$id-lane',
    label: id,
    kind: EditorLaneKind.video,
    hidden: hidden,
    clips: [
      for (var index = 0; index < actualSources.length; index++)
        EditorVideoClip(
          id: '$id-clip-$index',
          timelineStart: MediaTime.seconds(index * 2),
          duration: MediaTime.seconds(1),
          source: actualSources[index],
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(1),
          ),
        ),
    ],
  );
}

EditorLane feasibilityAudioLane(
  String id,
  MediaSource source, {
  bool muted = false,
}) => EditorLane(
  id: '$id-lane',
  label: id,
  kind: EditorLaneKind.audio,
  muted: muted,
  clips: [
    EditorAudioClip(
      id: '$id-clip',
      timelineStart: MediaTime.zero,
      duration: MediaTime.seconds(1),
      source: source,
      sourceRange: MediaRange(
        start: MediaTime.zero,
        duration: MediaTime.seconds(1),
      ),
    ),
  ],
);

EditorLane feasibilityCaptionLane(
  String id, {
  required int count,
  bool hidden = false,
}) => EditorLane(
  id: '$id-lane',
  label: id,
  kind: EditorLaneKind.captions,
  hidden: hidden,
  clips: [
    for (var index = 0; index < count; index++)
      EditorCaptionClip(
        id: '$id-clip-$index',
        timelineStart: MediaTime.seconds(index * 2),
        duration: MediaTime.seconds(1),
        text: 'Caption $index',
      ),
  ],
);
