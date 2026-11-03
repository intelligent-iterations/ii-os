import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

void main() => runApp(const EditorExampleApp());

final class EditorExampleApp extends StatelessWidget {
  const EditorExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const EditorExampleScreen(),
  );
}

final class EditorExampleScreen extends StatefulWidget {
  const EditorExampleScreen({super.key});

  @override
  State<EditorExampleScreen> createState() => _EditorExampleScreenState();
}

final class _EditorExampleScreenState extends State<EditorExampleScreen> {
  late EditorProject _project = _initialProject();
  MediaTime _playhead = MediaTime.seconds(2);
  EditorSelection? _selection;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IiFlutterVideoEditor(
        project: _project,
        playhead: _playhead,
        selection: _selection,
        onProjectChanged: (value) => setState(() => _project = value),
        onPlayheadChanged: (value) => setState(() => _playhead = value),
        onSelectionChanged: (value) => setState(() => _selection = value),
        onRenderRequested: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The host app now dispatches Universal FFmpeg.'),
          ),
        ),
        onAddCaptionRequested: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Open the host caption form at ${_playhead.inSeconds.toStringAsFixed(2)}s.',
            ),
          ),
        ),
      ),
    ),
  );

  EditorProject _initialProject() {
    const bytes = <int>[1, 2, 3, 4];
    final source = MediaSource(
      id: 'example-video',
      byteLength: bytes.length,
      fileExtension: 'mp4',
      openRead: () => Stream<List<int>>.value(bytes),
    );
    return EditorProject(
      id: 'example-project',
      width: 1280,
      height: 720,
      framesPerSecond: 30,
      duration: MediaTime.seconds(12),
      lanes: [
        EditorLane(
          id: 'video-lane',
          label: 'Video',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'opening-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(12),
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(12),
              ),
              fit: MediaFit.cover,
            ),
          ],
        ),
        EditorLane(
          id: 'caption-lane',
          label: 'Captions',
          kind: EditorLaneKind.captions,
          clips: [
            EditorCaptionClip(
              id: 'caption-one',
              timelineStart: MediaTime.seconds(1),
              duration: MediaTime.seconds(4),
              text: 'Edit locally. Upload only the result.',
              style: const EditorCaptionStyle(fontSize: 42),
            ),
          ],
        ),
      ],
    );
  }
}
