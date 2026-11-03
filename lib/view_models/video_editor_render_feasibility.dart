part of 'video_editor_projects_view_model.dart';

/// Structural admission for edits and every render-related side effect.
extension VideoEditorRenderFeasibility on VideoEditorProjectsViewModel {
  /// Applies a media addition only when the resulting project fits the exact
  /// target. Ordinary edits remain available so an opened over-limit project
  /// can be repaired over more than one step.
  bool applyStructurallyFeasibleAddition(EditorProject next) {
    final feasibility = _renderReadiness.inspect(next);
    final failure = _renderReadiness.failureFor(
      feasibility,
      intent: VideoEditorRenderIntent.edit,
    );
    if (!feasibility.isStructurallyFeasible) {
      _failure = failure;
      notifyListeners();
      return false;
    }
    _failure = null;
    applyTimeline(next);
    return true;
  }

  /// Re-checks the exact target before an action can cause external effects.
  bool requireStructurallyFeasible(VideoEditorRenderIntent intent) {
    final timeline = _timeline;
    if (timeline == null) return false;
    _failure = null;
    _renderFeasibility = _renderReadiness.inspect(timeline);
    _renderFeasibilityFailure = _renderReadiness.failureFor(
      _renderFeasibility!,
      intent: intent,
    );
    notifyListeners();
    return _renderFeasibility!.isStructurallyFeasible;
  }

  /// Runs [onAdmitted] only after the local-render guard has passed.
  ///
  /// The screen uses this boundary to keep engine creation behind structural
  /// feasibility, and tests can prove rejection without constructing FFmpeg.
  T? afterLocalRenderAdmission<T extends Object>(T Function() onAdmitted) {
    if (!requireStructurallyFeasible(VideoEditorRenderIntent.localRender)) {
      return null;
    }
    return onAdmitted();
  }

  void _refreshRenderFeasibility() {
    final timeline = _timeline;
    if (timeline == null) {
      _renderFeasibility = null;
      _renderFeasibilityFailure = null;
      return;
    }
    _renderFeasibility = _renderReadiness.inspect(timeline);
    _renderFeasibilityFailure = _renderReadiness.failureFor(
      _renderFeasibility!,
      intent: VideoEditorRenderIntent.edit,
    );
  }
}
