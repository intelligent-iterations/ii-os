import 'dart:io';

String? videoEditorNativeWorkspaceRoot() {
  if (!Platform.isLinux && !Platform.isMacOS) return null;
  final separator = Platform.pathSeparator;
  final temporaryRoot = Directory.systemTemp.absolute.path;
  final prefix = temporaryRoot.endsWith(separator)
      ? temporaryRoot
      : '$temporaryRoot$separator';
  // The universal runtime creates this absent directory itself, writes its
  // ownership marker, serializes recovery with a root lock, and accepts it on
  // later launches only while that marker remains valid.
  return '${prefix}ii_os_video_editor_workspaces_v1';
}
