import 'package:flutter/widgets.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';

typedef EditorPreviewBuilder =
    Widget Function(
      BuildContext context,
      EditorProject project,
      MediaTime position,
      EditorSelection? selection,
    );

typedef EditorLaneHeaderBuilder =
    Widget Function(BuildContext context, EditorLane lane);

typedef EditorClipBuilder =
    Widget Function(
      BuildContext context,
      EditorLane lane,
      EditorClip clip,
      bool selected,
    );

@immutable
final class EditorBuilders {
  const EditorBuilders({this.laneHeaderBuilder, this.clipBuilder});

  final EditorLaneHeaderBuilder? laneHeaderBuilder;
  final EditorClipBuilder? clipBuilder;
}
