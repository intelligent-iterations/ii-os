import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_timeline_codec.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/video_project.dart';
import 'package:ii_os/repositories/video_project_repository.dart';
import 'package:ii_os/screens/video_project_open_presentation.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/editor_render_dispatcher.dart';
import 'package:ii_os/services/editor_render_status_watcher.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';
import 'package:ii_os/services/video_editor_project.dart';
import 'package:ii_os/services/video_editor_render_readiness.dart';
import 'package:ii_os/services/video_project_media_gateway.dart';
import 'package:ii_os/view_models/video_editor_projects_view_model.dart';

part 'video_editor_projects_render_cases.dart';
part 'video_editor_project_open_cases.dart';
part 'video_editor_project_open_validation_cases.dart';
part 'video_editor_project_open_fixtures.dart';
part 'video_editor_projects_dispatcher_fake.dart';
part 'video_editor_render_guard_cases.dart';

LocalEditorMedia _media(String id) => LocalEditorMedia(
  id: id,
  filename: '$id.mp4',
  path: '',
  bytes: Uint8List.fromList(List<int>.filled(64, 7)),
  contentType: 'video/mp4',
  duration: const Duration(seconds: 9),
  hasVideo: true,
  hasAudio: false,
  width: 640,
  height: 360,
);

EditorProject _timeline({Duration duration = const Duration(seconds: 8)}) =>
    EditorProject(
      id: 'ii-os-project',
      width: 640,
      height: 360,
      framesPerSecond: 30,
      duration: MediaTime.microseconds(duration.inMicroseconds),
      lanes: [
        EditorLane(
          id: 'video-lane',
          label: 'Shot',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'video-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.microseconds(duration.inMicroseconds),
              source: _media('media-1').source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.microseconds(duration.inMicroseconds),
              ),
              sourceDuration: MediaTime.microseconds(
                duration.inMicroseconds <
                        const Duration(seconds: 9).inMicroseconds
                    ? const Duration(seconds: 9).inMicroseconds
                    : duration.inMicroseconds,
              ),
            ),
          ],
        ),
      ],
    );

final class _FakeProjects implements VideoProjectRepository {
  _FakeProjects({
    this.renderCapability = const EditorRenderCapability.available(),
  });
  final EditorRenderCapability renderCapability;
  final List<VideoProjectSummary> stored = [];
  JsonMap? savedTimeline;
  List<VideoProjectMediaRecord>? savedMedia;
  String? savedChange;
  String? savedRenderJobId;
  int creates = 0, saves = 0, reads = 0;
  int deletes = 0;
  int activeSaves = 0;
  int maxActiveSaves = 0;
  bool conflictOnSave = false;
  bool preserveStoredRenderJob = false;
  String? storedRenderJobId;
  final List<int> savedRevisions = [];
  final List<bool> savedClearRenderJobs = [];
  VideoProject? readable;
  Completer<VideoProject>? readCompleter;
  Completer<VideoProject>? createCompleter;
  Completer<void>? saveDelay;
  Completer<void>? deleteCompleter;
  Object? readFailure;
  Object? listFailure;

  VideoProject _project({
    required String id,
    String name = 'Untitled project',
    int revision = 0,
    JsonMap timeline = const {},
    List<VideoProjectMediaRecord> media = const [],
    List<VideoProjectChange> history = const [],
    String? renderJobId,
  }) => VideoProject(
    summary: VideoProjectSummary(
      id: id,
      name: name,
      duration: Duration.zero,
      clipCount: 0,
      mediaCount: media.length,
      revision: revision,
      updatedAt: DateTime(2026, 8, 23),
      updatedBy: 'user-1',
      renderJobId: renderJobId,
    ),
    timeline: timeline,
    media: media,
    history: history,
  );

  @override
  Future<VideoProject> create(String workspaceId, {String? name}) async {
    creates++;
    if (createCompleter case final pending?) return pending.future;
    final created = _project(id: 'project-1', name: name ?? 'Untitled project');
    stored.add(created.summary);
    return created;
  }

  @override
  Future<void> delete(String workspaceId, String projectId) async {
    deletes++;
    await deleteCompleter?.future;
    stored.removeWhere((entry) => entry.id == projectId);
  }

  @override
  Future<VideoProjectListing> list(String workspaceId) async {
    if (listFailure != null) throw listFailure!;
    return VideoProjectListing(
      projects: stored,
      renderCapability: renderCapability,
    );
  }

  @override
  Future<VideoProject> read(String workspaceId, String projectId) async {
    reads++;
    if (readFailure != null) throw readFailure!;
    if (readCompleter case final pending?) return pending.future;
    return readable ?? _project(id: projectId);
  }

  @override
  Future<VideoProject> save({
    required String workspaceId,
    required String projectId,
    required JsonMap timeline,
    required List<VideoProjectMediaRecord> media,
    required String change,
    required int revision,
    String? name,
    String? renderJobId,
    bool clearRenderJob = false,
  }) async {
    if (conflictOnSave) throw const VideoProjectConflict();
    saves++;
    activeSaves++;
    if (activeSaves > maxActiveSaves) maxActiveSaves = activeSaves;
    savedRevisions.add(revision);
    savedClearRenderJobs.add(clearRenderJob);
    savedTimeline = timeline;
    savedMedia = media;
    savedChange = change;
    final delay = saveDelay;
    saveDelay = null;
    try {
      await delay?.future;
      final effectiveRenderJobId = clearRenderJob
          ? null
          : renderJobId ?? (preserveStoredRenderJob ? storedRenderJobId : null);
      storedRenderJobId = effectiveRenderJobId;
      savedRenderJobId = effectiveRenderJobId;
      return _project(
        id: projectId,
        revision: revision + 1,
        timeline: timeline,
        media: media,
        renderJobId: effectiveRenderJobId,
        history: [
          VideoProjectChange(
            at: DateTime(2026, 8, 23),
            by: 'user-1',
            description: change,
            revision: revision + 1,
          ),
        ],
      );
    } finally {
      activeSaves--;
    }
  }
}

final class _FakeGateway implements VideoProjectMediaGateway {
  int uploads = 0;
  int restoreCalls = 0;
  final List<String> held = [];
  List<LocalEditorMedia> restorable = const [];
  Object? restoreFailure;
  Completer<void>? publishDelay, restoreDelay;

  @override
  Future<List<VideoProjectMediaRecord>> publish({
    required String workspaceId,
    required String expectedBucket,
    required List<LocalEditorMedia> media,
    Map<String, VideoProjectMediaOrigin> knownOrigins = const {},
    Map<String, VideoProjectMediaRecord> alreadyStored = const {},
    bool ghostMode = false,
  }) async {
    await publishDelay?.future;
    final records = <VideoProjectMediaRecord>[];
    for (final item in media) {
      final known = alreadyStored[item.id];
      if (known != null && known.byteLength == item.bytes.length) {
        records.add(known);
        continue;
      }
      final origin = knownOrigins[item.id];
      if (origin != null) {
        held.add(item.id);
        records.add(
          VideoProjectMediaRecord(
            id: item.id,
            filename: item.filename,
            contentType: item.contentType,
            byteLength: item.bytes.length,
            duration: item.duration,
            hasVideo: item.hasVideo,
            hasAudio: item.hasAudio,
            origin: origin,
          ),
        );
        continue;
      }
      uploads++;
      records.add(
        VideoProjectMediaRecord(
          id: item.id,
          filename: item.filename,
          contentType: item.contentType,
          byteLength: item.bytes.length,
          duration: item.duration,
          hasVideo: item.hasVideo,
          hasAudio: item.hasAudio,
          width: item.width,
          height: item.height,
          origin: WorkspaceSourceAssetOrigin('asset-${item.id}'),
        ),
      );
    }
    return records;
  }

  @override
  Future<List<LocalEditorMedia>> restore({
    required String workspaceId,
    required String expectedBucket,
    required List<VideoProjectMediaRecord> media,
  }) async {
    restoreCalls++;
    final delay = restoreDelay;
    restoreDelay = null;
    await delay?.future;
    if (restoreFailure != null) throw restoreFailure!;
    return restorable;
  }
}

VideoEditorProjectsViewModel _model(
  _FakeProjects projects,
  _FakeGateway gateway, {
  EditorRenderDispatcher? dispatcher,
  EditorRenderStatusWatcher? renderWatcher,
  VideoEditorRenderReadinessService? renderReadiness,
}) => VideoEditorProjectsViewModel(
  projects: projects,
  mediaGateway: gateway,
  renderDispatcher: dispatcher,
  renderWatcher: renderWatcher ?? _FakeRenderWatcher(),
  renderReadiness: renderReadiness,
  workspaceId: 'workspace-1',
  expectedBucket: 'bucket-1',
);

void main() {
  test('a fresh editor has nothing open and nothing to undo', () {
    final model = _model(_FakeProjects(), _FakeGateway());

    expect(model.current, isNull);
    expect(model.timeline, isNull);
    expect(model.isDirty, isFalse);
    expect(model.canUndo, isFalse);
    expect(model.canRedo, isFalse);
  });

  test('each accepted timeline names what changed', () {
    final model = _model(_FakeProjects(), _FakeGateway())
      ..adoptTimeline(_timeline())
      ..applyTimeline(
        sliceEditorProject(project: _timeline(), at: MediaTime.seconds(4)),
      );

    expect(model.unsavedChanges, ['Cut a clip']);
    expect(model.isDirty, isTrue);
    expect(model.canUndo, isTrue);
  });

  test('undo goes back a step and redo comes forward again', () {
    final cut = sliceEditorProject(
      project: _timeline(),
      at: MediaTime.seconds(4),
    );
    final model = _model(_FakeProjects(), _FakeGateway())
      ..adoptTimeline(_timeline())
      ..applyTimeline(cut);

    final undone = model.undo();
    expect(undone!.laneById('video-lane')!.clips, hasLength(1));
    expect(model.canRedo, isTrue);
    expect(model.unsavedChanges, isEmpty);

    final redone = model.redo();
    expect(redone!.laneById('video-lane')!.clips, hasLength(2));
    expect(model.canUndo, isTrue);
  });

  test('undo stops rather than growing without bound', () {
    final model = _model(_FakeProjects(), _FakeGateway())
      ..adoptTimeline(_timeline());
    for (var step = 0; step < videoEditorUndoDepth + 20; step++) {
      model.applyTimeline(_timeline(duration: Duration(seconds: 8 + step)));
    }

    var steps = 0;
    while (model.undo() != null) {
      steps++;
    }
    expect(steps, videoEditorUndoDepth);
  });

  test('saving stores the timeline and clears what was pending', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway();
    final model = _model(projects, gateway);
    await model.createProject(name: 'Trailer');
    model
      ..adoptTimeline(_timeline())
      ..applyTimeline(
        sliceEditorProject(project: _timeline(), at: MediaTime.seconds(4)),
      );

    expect(await model.save(media: [_media('media-1')]), isTrue);
    expect(projects.savedChange, 'Cut a clip');
    expect(projects.savedTimeline!['version'], editorTimelineVersion);
    expect(gateway.uploads, 1);
    expect(model.isDirty, isFalse);
    expect(model.unsavedChanges, isEmpty);
    expect(model.current!.revision, 1);
  });

  test('a second save leaves already stored media alone', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway();
    final model = _model(projects, gateway);
    await model.createProject();
    model.adoptTimeline(_timeline());
    await model.save(media: [_media('media-1')]);
    model.applyTimeline(_timeline(duration: const Duration(seconds: 7)));
    await model.save(media: [_media('media-1')]);

    expect(gateway.uploads, 1);
    expect(projects.saves, 2);
  });

  test('several changes are summarised into one history line', () async {
    final projects = _FakeProjects();
    final model = _model(projects, _FakeGateway());
    await model.createProject();
    model.adoptTimeline(_timeline());
    for (var step = 1; step <= 3; step++) {
      model.applyTimeline(_timeline(duration: Duration(seconds: 8 + step)));
    }
    await model.save(media: [_media('media-1')]);

    expect(projects.savedChange, contains('and 2 more changes'));
  });

  test('saving without a timeline says what to do instead', () async {
    final model = _model(_FakeProjects(), _FakeGateway());
    await model.createProject();

    expect(await model.save(media: const []), isFalse);
    expect(model.failure, 'Add some media before saving this project.');
  });

  test('a save someone else beat says so in words', () async {
    final projects = _FakeProjects()..conflictOnSave = true;
    final model = _model(projects, _FakeGateway());
    await model.createProject();
    model.applyTimeline(_timeline());

    expect(await model.save(media: [_media('media-1')]), isFalse);
    expect(model.failure, contains('Someone else saved this project'));
    expect(model.isDirty, isTrue);
    expect(model.unsavedChanges, isNotEmpty);
  });

  test('opening a project puts its timeline and media back', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restorable = [_media('media-1')];
    final saved = _timeline();
    projects.readable = VideoProject(
      summary: VideoProjectSummary(
        id: 'project-1',
        name: 'Trailer',
        duration: const Duration(seconds: 8),
        clipCount: 1,
        mediaCount: 1,
        revision: 4,
        updatedAt: DateTime(2026, 8, 23),
        updatedBy: 'user-1',
      ),
      timeline: encodeEditorTimeline(saved),
      media: [
        VideoProjectMediaRecord(
          id: 'media-1',
          filename: 'media-1.mp4',
          contentType: 'video/mp4',
          byteLength: 64,
          duration: const Duration(seconds: 9),
          hasVideo: true,
          hasAudio: false,
          origin: const WorkspaceSourceAssetOrigin('asset-1'),
        ),
      ],
      history: const [],
    );
    final model = _model(projects, gateway);

    final opened = await model.openProject('project-1');
    expect(opened, isA<VideoProjectOpened>());
    final accepted = opened as VideoProjectOpened;
    expect(accepted.timeline!.laneById('video-lane')!.clips, hasLength(1));
    expect(accepted.media, hasLength(1));
    expect(model.current!.name, 'Trailer');
    expect(model.isDirty, isFalse);
    expect(model.canUndo, isFalse);
  });

  test('a project whose media is gone names the file', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()
      ..restoreFailure = const VideoProjectMediaMissing('opening-shot.mp4');
    projects.readable = VideoProject(
      summary: VideoProjectSummary(
        id: 'project-1',
        name: 'Trailer',
        duration: const Duration(seconds: 8),
        clipCount: 1,
        mediaCount: 1,
        revision: 1,
        updatedAt: DateTime(2026, 8, 23),
        updatedBy: 'user-1',
      ),
      timeline: encodeEditorTimeline(_timeline()),
      media: [_mediaRecord('media-1')],
      history: const [],
    );

    final model = _model(projects, gateway);
    expect(
      await model.openProject('project-1'),
      isA<VideoProjectOpenRejected>(),
    );
    expect(model.failure, contains('opening-shot.mp4'));
  });

  test('a listing that fails says so without a stack trace', () async {
    final projects = _FakeProjects();
    final model = _model(projects, _FakeGateway());
    projects.readFailure = StateError('boom');

    await model.load();
    expect(model.failure, isNull);
    expect(model.listFailure, isNull);

    expect(
      await model.openProject('project-1'),
      isA<VideoProjectOpenRejected>(),
    );
    expect(model.failure, 'That project could not be opened.');
    expect(model.failure, isNot(contains('boom')));
  });

  test(
    'a project list that fails stays beside the list, not on the page',
    () async {
      final projects = _FakeProjects()..listFailure = StateError('offline');
      final model = _model(projects, _FakeGateway());

      await model.load();
      expect(model.failure, isNull);
      expect(
        model.listFailure,
        'The projects saved in this workspace could not be listed.',
      );
    },
  );

  test(
    'removing the open project leaves the editor with nothing open',
    () async {
      final projects = _FakeProjects();
      final model = _model(projects, _FakeGateway());
      await model.createProject();
      model.adoptTimeline(_timeline());

      expect(await model.deleteProject('project-1'), isTrue);
      expect(model.current, isNull);
      expect(model.timeline, isNull);
      expect(model.saved, isEmpty);
    },
  );

  test('media already in the workspace is held, not copied', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway();
    final model = _model(projects, gateway);
    await model.createProject();
    model.applyTimeline(_timeline());

    expect(
      await model.save(
        media: [_media('media-1')],
        origins: const {
          'media-1': WorkspaceArtifactOrigin(
            jobId: 'job-7',
            path: 'workspaces/w/runs/job-7/video/out.mp4',
            generation: '3',
            sizeBytes: 64,
            sha256: 'aa',
            contentType: 'video/mp4',
          ),
        },
      ),
      isTrue,
    );
    expect(gateway.uploads, 0, reason: 'nothing was copied');
    expect(gateway.held, ['media-1']);
  });

  test('media from someone\'s own machine has nowhere else to live', () async {
    final gateway = _FakeGateway();
    final model = _model(_FakeProjects(), gateway);
    await model.createProject();
    model.applyTimeline(_timeline());

    await model.save(media: [_media('media-1')]);
    expect(gateway.uploads, 1);
    expect(gateway.held, isEmpty);
  });

  videoEditorRenderTests();
  videoEditorProjectOpenTests();
  videoEditorProjectOpenValidationTests();
  videoEditorRenderGuardTests();
}
