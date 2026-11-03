part of 'video_editor_projects_view_model_test.dart';

VideoProject _storedProject(
  _FakeProjects projects, {
  required String id,
  JsonMap timeline = const {},
  List<VideoProjectMediaRecord> media = const [],
  String? renderJobId,
  int revision = 0,
}) => projects._project(
  id: id,
  timeline: timeline,
  media: media,
  renderJobId: renderJobId,
  revision: revision,
);

VideoProjectMediaRecord _mediaRecord(String id) => VideoProjectMediaRecord(
  id: id,
  filename: '$id.mp4',
  contentType: 'video/mp4',
  byteLength: 64,
  duration: const Duration(seconds: 9),
  hasVideo: true,
  hasAudio: false,
  origin: WorkspaceSourceAssetOrigin('asset-$id'),
);
