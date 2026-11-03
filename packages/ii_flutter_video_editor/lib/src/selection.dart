import 'package:meta/meta.dart';

@immutable
final class EditorSelection {
  const EditorSelection({required this.laneId, required this.clipId});

  final String laneId;
  final String clipId;

  @override
  bool operator ==(Object other) =>
      other is EditorSelection &&
      other.laneId == laneId &&
      other.clipId == clipId;

  @override
  int get hashCode => Object.hash(laneId, clipId);
}
