import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  test('image overlay is added as a resizable top-most lane', () {
    final project = testProject();
    final overlaid = addEditorImageOverlay(
      project: project,
      laneId: 'brand-layer',
      clipId: 'brand-image',
      source: testSource('brand-source', 'png'),
      timelineStart: MediaTime.seconds(1),
      duration: MediaTime.seconds(4),
    );

    final lane = overlaid.lanes.last;
    final clip = lane.clips.single as EditorVideoClip;
    expect(lane.id, 'brand-layer');
    expect(isEditorImageClip(clip), isTrue);
    expect(clip.destination.width, 0.35);
    expect(clip.timelineStart, MediaTime.seconds(1));
    expect(() => validateEditorProject(overlaid), returnsNormally);

    final resized = setEditorVisualDestination(
      project: overlaid,
      selection: const EditorSelection(
        laneId: 'brand-layer',
        clipId: 'brand-image',
      ),
      destination: const MediaRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6),
    );
    final resizedClip = resized.clipById('brand-image')! as EditorVideoClip;
    expect(resizedClip.destination.width, 0.5);
    expect(resizedClip.destination.height, 0.6);
  });

  test('image overlay rejects non-image input', () {
    expect(
      () => addEditorImageOverlay(
        project: testProject(),
        laneId: 'not-an-image-layer',
        clipId: 'not-an-image',
        source: testSource('movie-source', 'mp4'),
        timelineStart: MediaTime.zero,
        duration: MediaTime.seconds(2),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('lane switches and ordering produce validated projects', () {
    final project = testProject();
    final muted = updateEditorLane(
      project: project,
      laneId: 'audio-lane',
      muted: true,
      locked: true,
    );
    expect(muted.laneById('audio-lane')!.muted, isTrue);
    expect(muted.laneById('audio-lane')!.locked, isTrue);

    final moved = moveEditorLane(
      project: muted,
      laneId: 'caption-lane',
      toIndex: 0,
    );
    expect(moved.lanes.first.id, 'caption-lane');
    expect(() => validateEditorProject(moved), returnsNormally);
  });
}
