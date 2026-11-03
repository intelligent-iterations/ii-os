/// Where an export is compressed and written.
enum EditorExportTarget {
  /// In this browser or app, the way it has always worked. Nothing leaves
  /// until the video is finished, and the tab has to stay open.
  thisDevice,

  /// On a workspace machine. The tab is free the moment the work is handed
  /// over, and the finished video appears in the workspace library.
  workspaceMachine,
}
