import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_change_description.dart';

MediaSource _source(String id) => MediaSource(
  id: id,
  byteLength: 8,
  fileExtension: 'mp4',
  openRead: () => Stream<List<int>>.value(const [1, 2, 3, 4, 5, 6, 7, 8]),
);

EditorProject _base({bool linked = false}) => EditorProject(
  id: 'project',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(10),
  lanes: [
    EditorLane(
      id: 'video-lane',
      label: 'Video',
      kind: EditorLaneKind.video,
      clips: [
        EditorVideoClip(
          id: 'video-clip',
          linkGroupId: linked ? 'pair' : null,
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(8),
          source: _source('media-1'),
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(8),
          ),
          sourceDuration: MediaTime.seconds(9),
        ),
      ],
    ),
    EditorLane(
      id: 'audio-lane',
      label: 'Audio',
      kind: EditorLaneKind.audio,
      clips: [
        EditorAudioClip(
          id: 'audio-clip',
          linkGroupId: linked ? 'pair' : null,
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(8),
          source: _source('media-1'),
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(8),
          ),
          sourceDuration: MediaTime.seconds(9),
        ),
      ],
    ),
  ],
);

void main() {
  test('names a cut', () {
    final after = sliceEditorProject(
      project: _base(),
      at: MediaTime.seconds(4),
    );

    expect(describeEditorChange(_base(), after), 'Cut 2 lanes');
  });

  test('names a span that came out', () {
    final after = removeEditorSpan(
      project: _base(),
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );

    expect(
      describeEditorChange(_base(), after),
      'Removed 2.0 seconds from the timeline',
    );
  });

  test('names a picture coming apart from its sound', () {
    final before = _base(linked: true);
    final after = detachEditorClipAudio(
      project: before,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
    );

    expect(
      describeEditorChange(before, after),
      'Separated a picture from its sound',
    );
  });

  test('names a transition that arrived', () {
    final before = _base();
    final after = setEditorClipTransition(
      project: before,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      transition: EditorTransition(
        kind: EditorTransitionKind.dissolve,
        duration: MediaTime.seconds(1),
      ),
    );

    expect(describeEditorChange(before, after), 'Added a cross dissolve');
  });

  test('names a transition that changed', () {
    final before = setEditorClipTransition(
      project: _base(),
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      transition: EditorTransition(
        kind: EditorTransitionKind.dissolve,
        duration: MediaTime.seconds(1),
      ),
    );
    final after = setEditorClipTransition(
      project: before,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      transition: EditorTransition(
        kind: EditorTransitionKind.dipToColor,
        duration: MediaTime.seconds(1),
      ),
    );

    expect(
      describeEditorChange(before, after),
      'Changed a transition to a dip to colour',
    );
  });

  test('names a transition that went away', () {
    final before = setEditorClipTransition(
      project: _base(),
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      transition: EditorTransition(
        kind: EditorTransitionKind.dissolve,
        duration: MediaTime.seconds(1),
      ),
    );
    final after = clearEditorClipTransition(
      project: before,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
    );

    expect(describeEditorChange(before, after), 'Removed a transition');
  });

  test('names a clip that moved', () {
    final before = _base();
    final after = moveEditorClip(
      project: before,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      targetLaneId: 'video-lane',
      timelineStart: MediaTime.seconds(1),
    );

    expect(describeEditorChange(before, after), 'Moved a clip');
  });

  test('names a clip that was trimmed', () {
    final before = _base();
    final after = trimEditorClip(
      project: before,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      edge: EditorTrimEdge.end,
      edgeTime: MediaTime.seconds(6),
    );

    expect(describeEditorChange(before, after), 'Trimmed a clip');
  });

  test('names a caption that was added', () {
    final before = _base();
    final after = before.copyWith(
      lanes: [
        ...before.lanes,
        EditorLane(
          id: 'caption-lane',
          label: 'Subtitle',
          kind: EditorLaneKind.captions,
          clips: [
            EditorCaptionClip(
              id: 'caption-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(3),
              text: 'Hello',
            ),
          ],
        ),
      ],
    );

    expect(describeEditorChange(before, after), 'Added a caption');
  });

  test('names a caption added to an existing lane', () {
    final before = _base().copyWith(
      lanes: [
        ..._base().lanes,
        EditorLane(
          id: 'caption-lane',
          label: 'Captions',
          kind: EditorLaneKind.captions,
          clips: [
            EditorCaptionClip(
              id: 'first-caption',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(3),
              text: 'First',
            ),
          ],
        ),
      ],
    );
    final lane = before.lanes.last;
    final after = before.copyWith(
      lanes: [
        ...before.lanes.take(before.lanes.length - 1),
        lane.copyWith(
          clips: [
            ...lane.clips,
            EditorCaptionClip(
              id: 'second-caption',
              timelineStart: MediaTime.seconds(3),
              duration: MediaTime.seconds(3),
              text: 'Second',
            ),
          ],
        ),
      ],
    );

    expect(describeEditorChange(before, after), 'Added a caption');
  });

  test('still names a split caption as a cut', () {
    final before = _base().copyWith(
      lanes: [
        ..._base().lanes,
        EditorLane(
          id: 'caption-lane',
          label: 'Captions',
          kind: EditorLaneKind.captions,
          clips: [
            EditorCaptionClip(
              id: 'caption-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(4),
              text: 'One cue',
            ),
          ],
        ),
      ],
    );
    final after = splitEditorClip(
      project: before,
      selection: const EditorSelection(
        laneId: 'caption-lane',
        clipId: 'caption-clip',
      ),
      at: MediaTime.seconds(2),
    ).project;

    expect(describeEditorChange(before, after), 'Cut a clip');
  });

  test('names media that was added', () {
    final before = _base();
    final after = before.copyWith(
      lanes: [
        ...before.lanes,
        EditorLane(
          id: 'video-lane-2',
          label: 'Second shot',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'video-clip-2',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(5),
              source: _source('media-2'),
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(5),
              ),
              sourceDuration: MediaTime.seconds(5),
            ),
          ],
        ),
      ],
    );

    expect(describeEditorChange(before, after), 'Added Second shot');
  });

  test('names a change to how the export is compressed', () {
    final before = _base();
    final after = before.copyWith(
      output: const MediaOutputSettings(videoBitrate: 8000000),
    );

    expect(describeEditorChange(before, after), 'Set the export to 8.0 Mbps');
  });

  test('falls back to something true rather than something specific', () {
    final before = _base();
    final after = before.copyWith(backgroundColor: 'FFFFFF');

    expect(describeEditorChange(before, after), 'Edited the timeline');
  });
}
