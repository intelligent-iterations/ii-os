import 'dart:io';
import 'dart:isolate';

import 'package:ii_ffmpeg_universal/src/backends/io_workspace.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: workspace_crash_fixture.dart ROOT');
    exitCode = 64;
    return;
  }
  final workspace = await IoWorkspace.create(
    'killed_child',
    root: Directory(arguments.single),
  );
  stdout.writeln('WORKSPACE=${workspace.directory.path}');
  await stdout.flush();
  // An unresolved Future does not keep a Dart isolate alive when its event
  // queue is otherwise empty. A receive port does, which makes this fixture a
  // deterministic stand-in for a process killed after publishing ownership.
  final keepAlive = ReceivePort();
  await keepAlive.first;
}
