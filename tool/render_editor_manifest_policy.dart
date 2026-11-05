import 'dart:io';

/// The two decisions `render_editor_manifest.dart` makes before FFmpeg runs,
/// kept apart from the render itself so they are testable without an engine.

/// The file a render input arrives as. A render names its inputs by plain
/// file name; anything that could address a path outside the input directory
/// is refused rather than resolved.
File renderInputFile(Directory inputDirectory, String name) {
  if (name.isEmpty ||
      name.contains('/') ||
      name.contains(r'\') ||
      name == '.' ||
      name == '..') {
    throw StateError('A render input may not name a path: $name.');
  }
  return File.fromUri(inputDirectory.uri.resolve(name));
}

/// An export is allowed a generous multiple of its own running time, because a
/// workspace machine encodes on a CPU rather than a browser's, and then a hard
/// ceiling so a wedged render cannot hold a runner all day.
Duration renderTimeoutFor(Duration expected) {
  final scaled = expected * 20;
  if (scaled < const Duration(minutes: 5)) return const Duration(minutes: 5);
  if (scaled > const Duration(minutes: 30)) return const Duration(minutes: 30);
  return scaled;
}
