part of 'video_editor_projects_view_model.dart';

/// Closing or removing the durable project that owns the current edit.
extension VideoEditorProjectLifecycle on VideoEditorProjectsViewModel {
  Future<bool> deleteProject(String projectId) async {
    if (_hasProjectOperation) return false;
    final deletingOpenProject = _open?.id == projectId;
    final watchedRenderJob = deletingOpenProject ? _renderJobId : null;
    if (deletingOpenProject) _renderWatcher.stop();
    _failure = null;
    setBusyForObject(VideoProjectBusy.delete, true);
    try {
      await _projects.delete(workspaceId, projectId);
      _saved = _saved.where((entry) => entry.id != projectId).toList();
      if (deletingOpenProject && _open?.id == projectId) {
        _replaceRenderJob(null);
        _open = null;
        _adoptTimeline(null);
      }
      notifyListeners();
      return true;
    } on Object {
      _failure = 'That project could not be removed.';
      if (deletingOpenProject &&
          watchedRenderJob != null &&
          _open?.id == projectId &&
          _renderJobId == watchedRenderJob) {
        _watchRenderJob(watchedRenderJob);
      }
      notifyListeners();
      return false;
    } finally {
      setBusyForObject(VideoProjectBusy.delete, false);
    }
  }

  bool closeProject() {
    if (_hasProjectOperation) return false;
    _renderWatcher.stop();
    _replaceRenderJob(null);
    _open = null;
    _adoptTimeline(null);
    return true;
  }
}
