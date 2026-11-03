import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

MediaSource testSource(String id, String extension) {
  const bytes = <int>[1, 2, 3, 4];
  return MediaSource(
    id: id,
    byteLength: bytes.length,
    fileExtension: extension,
    openRead: () => Stream<List<int>>.value(bytes),
  );
}

EditorProject testProject({
  bool lockedVideo = false,
  bool mutedAudio = false,
  bool hiddenCaptions = false,
  bool linkPrimaryMedia = false,
  MediaSource? videoSource,
  MediaSource? audioSource,
}) {
  final video = videoSource ?? testSource('video-source', 'mp4');
  final audio = audioSource ?? testSource('audio-source', 'm4a');
  return EditorProject(
    id: 'project-1',
    width: 640,
    height: 360,
    framesPerSecond: 30,
    duration: MediaTime.seconds(10),
    lanes: [
      EditorLane(
        id: 'video-lane',
        label: 'Video',
        kind: EditorLaneKind.video,
        locked: lockedVideo,
        clips: [
          EditorVideoClip(
            id: 'video-clip',
            linkGroupId: linkPrimaryMedia ? 'primary-media' : null,
            timelineStart: MediaTime.zero,
            duration: MediaTime.seconds(8),
            source: video,
            sourceRange: MediaRange(
              start: MediaTime.seconds(1),
              duration: MediaTime.seconds(8),
            ),
            fit: MediaFit.cover,
          ),
        ],
      ),
      EditorLane(
        id: 'audio-lane',
        label: 'Audio',
        kind: EditorLaneKind.audio,
        muted: mutedAudio,
        clips: [
          EditorAudioClip(
            id: 'audio-clip',
            linkGroupId: linkPrimaryMedia ? 'primary-media' : null,
            timelineStart: MediaTime.zero,
            duration: MediaTime.seconds(8),
            source: audio,
            sourceRange: MediaRange(
              start: MediaTime.zero,
              duration: MediaTime.seconds(8),
            ),
          ),
        ],
      ),
      EditorLane(
        id: 'caption-lane',
        label: 'Captions',
        kind: EditorLaneKind.captions,
        hidden: hiddenCaptions,
        clips: [
          EditorCaptionClip(
            id: 'caption-clip',
            timelineStart: MediaTime.seconds(2),
            duration: MediaTime.seconds(3),
            text: 'Client-side editing',
            style: const EditorCaptionStyle(fontSize: 24),
          ),
        ],
      ),
    ],
  );
}
