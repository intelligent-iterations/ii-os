import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_timeline_codec.dart';

MediaSource _source(String id) => MediaSource(
  id: id,
  byteLength: 8,
  fileExtension: 'mp4',
  openRead: () => Stream<List<int>>.value(const [1, 2, 3, 4, 5, 6, 7, 8]),
);

EditorProject _project() => EditorProject(
  id: 'ii-os-project',
  width: 1280,
  height: 720,
  framesPerSecond: 30,
  duration: MediaTime.seconds(12),
  backgroundColor: '101014',
  output: const MediaOutputSettings(
    container: MediaContainer.webm,
    videoCodec: MediaVideoCodec.vp9,
    audioCodec: MediaAudioCodec.opus,
    videoBitrate: 3000000,
    audioBitrate: 96000,
  ),
  lanes: [
    EditorLane(
      id: 'video-lane',
      label: 'Opening shot',
      kind: EditorLaneKind.video,
      locked: true,
      clips: [
        EditorVideoClip(
          id: 'clip-a',
          linkGroupId: 'pair-1',
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(4),
          source: _source('media-1'),
          sourceRange: MediaRange(
            start: MediaTime.seconds(1),
            duration: MediaTime.seconds(4),
          ),
          sourceDuration: MediaTime.seconds(9),
          destination: const MediaRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
          fit: MediaFit.cover,
          opacity: 0.75,
        ),
        EditorVideoClip(
          id: 'clip-b',
          timelineStart: MediaTime.seconds(4),
          duration: MediaTime.seconds(4),
          source: _source('media-2'),
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(4),
          ),
          sourceDuration: MediaTime.seconds(6),
          transition: EditorTransition(
            kind: EditorTransitionKind.slideFromLeft,
            duration: MediaTime.milliseconds(750),
            color: 'FFAA00',
          ),
        ),
      ],
    ),
    EditorLane(
      id: 'audio-lane',
      label: 'Opening sound',
      kind: EditorLaneKind.audio,
      muted: true,
      clips: [
        EditorAudioClip(
          id: 'clip-c',
          linkGroupId: 'pair-1',
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(4),
          source: _source('media-1'),
          sourceRange: MediaRange(
            start: MediaTime.seconds(1),
            duration: MediaTime.seconds(4),
          ),
          sourceDuration: MediaTime.seconds(9),
          volume: 0.5,
        ),
      ],
    ),
    EditorLane(
      id: 'caption-lane',
      label: 'Subtitle',
      kind: EditorLaneKind.captions,
      hidden: true,
      clips: [
        EditorCaptionClip(
          id: 'clip-d',
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(3),
          text: 'Opening line',
          destination: const MediaRect(
            x: 0.08,
            y: 0.78,
            width: 0.84,
            height: 0.16,
          ),
          style: const EditorCaptionStyle(
            fontSize: 42,
            fontWeight: 700,
            textColor: 0xffeeeeee,
            backgroundColor: 0x66000000,
            maxLines: 2,
            textAlign: EditorTextAlign.left,
            fontFamily: 'Manrope',
          ),
        ),
      ],
    ),
  ],
);

Map<String, MediaSource> get _sources => {
  'media-1': _source('media-1'),
  'media-2': _source('media-2'),
};

void main() {
  test('a timeline survives a trip through storage unchanged', () {
    final original = _project();
    final restored = decodeEditorTimeline(
      encodeEditorTimeline(original),
      sources: _sources,
    );

    expect(restored.id, original.id);
    expect(restored.width, 1280);
    expect(restored.height, 720);
    expect(restored.framesPerSecond, 30);
    expect(restored.duration, MediaTime.seconds(12));
    expect(restored.backgroundColor, '101014');
    expect(restored.output.container, MediaContainer.webm);
    expect(restored.output.videoCodec, MediaVideoCodec.vp9);
    expect(restored.output.audioCodec, MediaAudioCodec.opus);
    expect(restored.output.videoBitrate, 3000000);
    expect(restored.output.audioBitrate, 96000);
    expect(() => validateEditorProject(restored), returnsNormally);
  });

  test('lane switches and link groups come back as they were', () {
    final restored = decodeEditorTimeline(
      encodeEditorTimeline(_project()),
      sources: _sources,
    );

    final video = restored.laneById('video-lane')!;
    expect(video.label, 'Opening shot');
    expect(video.locked, isTrue);
    expect(restored.laneById('audio-lane')!.muted, isTrue);
    expect(restored.laneById('caption-lane')!.hidden, isTrue);
    expect(restored.clipById('clip-a')!.linkGroupId, 'pair-1');
    expect(restored.clipById('clip-c')!.linkGroupId, 'pair-1');
  });

  test('a picture clip keeps its framing and its source window', () {
    final restored = decodeEditorTimeline(
      encodeEditorTimeline(_project()),
      sources: _sources,
    );

    final clip = restored.clipById('clip-a')! as EditorVideoClip;
    expect(clip.source.id, 'media-1');
    expect(clip.sourceRange.start, MediaTime.seconds(1));
    expect(clip.sourceDuration, MediaTime.seconds(9));
    expect(clip.destination.x, closeTo(0.1, 1e-9));
    expect(clip.destination.height, closeTo(0.4, 1e-9));
    expect(clip.fit, MediaFit.cover);
    expect(clip.opacity, closeTo(0.75, 1e-9));
  });

  test('a transition keeps its kind, its length, and its colour', () {
    final restored = decodeEditorTimeline(
      encodeEditorTimeline(_project()),
      sources: _sources,
    );

    final transition =
        (restored.clipById('clip-b')! as EditorVideoClip).transition!;
    expect(transition.kind, EditorTransitionKind.slideFromLeft);
    expect(transition.duration, MediaTime.milliseconds(750));
    expect(transition.color, 'FFAA00');
  });

  test('a caption keeps every part of how it looks', () {
    final restored = decodeEditorTimeline(
      encodeEditorTimeline(_project()),
      sources: _sources,
    );

    final caption = restored.clipById('clip-d')! as EditorCaptionClip;
    expect(caption.text, 'Opening line');
    expect(caption.style.fontSize, 42);
    expect(caption.style.fontWeight, 700);
    expect(caption.style.textColor, 0xffeeeeee);
    expect(caption.style.backgroundColor, 0x66000000);
    expect(caption.style.maxLines, 2);
    expect(caption.style.textAlign, EditorTextAlign.left);
    expect(caption.style.fontFamily, 'Manrope');
  });

  test('an ordered multi-cue caption lane round-trips canonically', () {
    final original = _project();
    final lane = original.laneById('caption-lane')!;
    final withTwoCues = original.copyWith(
      lanes: [
        original.lanes[0],
        original.lanes[1],
        lane.copyWith(
          clips: [
            ...lane.clips,
            EditorCaptionClip(
              id: 'clip-e',
              timelineStart: MediaTime.seconds(3),
              duration: MediaTime.seconds(2),
              text: 'Second line',
              destination: const MediaRect(
                x: 0.1,
                y: 0.1,
                width: 0.8,
                height: 0.24,
              ),
              style: const EditorCaptionStyle(
                fontSize: 56,
                backgroundColor: 0x66000000,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ],
    );
    final encoded = encodeEditorTimeline(withTwoCues);
    final restored = decodeEditorTimeline(encoded, sources: _sources);

    final restoredLane = restored.laneById('caption-lane')!;
    expect(restoredLane.clips.map((clip) => clip.id), ['clip-d', 'clip-e']);
    expect(restoredLane.hidden, isTrue);
    final second = restoredLane.clips.last as EditorCaptionClip;
    expect(second.timelineStart, MediaTime.seconds(3));
    expect(second.duration, MediaTime.seconds(2));
    expect(second.text, 'Second line');
    expect(second.destination.y, closeTo(0.1, 1e-9));
    expect(second.style.fontSize, 56);
    expect(encodeEditorTimeline(restored), encoded);
  });

  test('a sound clip keeps how loud it was set', () {
    final restored = decodeEditorTimeline(
      encodeEditorTimeline(_project()),
      sources: _sources,
    );

    expect(
      (restored.clipById('clip-c')! as EditorAudioClip).volume,
      closeTo(0.5, 1e-9),
    );
  });

  test('names the clip whose media is no longer in the workspace', () {
    final encoded = encodeEditorTimeline(_project());

    expect(
      () => decodeEditorTimeline(
        encoded,
        sources: {'media-1': _source('media-1')},
      ),
      throwsA(
        isA<EditorTimelineDecodeFailure>().having(
          (failure) => failure.missingMediaIds,
          'missingMediaIds',
          ['media-2'],
        ),
      ),
    );
  });

  test('reads the media a timeline needs before opening it', () {
    expect(
      editorTimelineMediaIds(encodeEditorTimeline(_project())),
      unorderedEquals(<String>['media-1', 'media-2']),
    );
  });

  test('refuses a document written by a newer version', () {
    final encoded = {...encodeEditorTimeline(_project()), 'version': 99};

    expect(
      () => decodeEditorTimeline(encoded, sources: _sources),
      throwsA(isA<EditorTimelineDecodeFailure>()),
    );
  });

  test('refuses a document that is not a timeline at all', () {
    expect(
      () => decodeEditorTimeline(const {'version': 1}, sources: _sources),
      throwsA(isA<EditorTimelineDecodeFailure>()),
    );
  });
}
