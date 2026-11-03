import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/src/backends/io_workspace.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'killed subprocess state is reclaimed without touching other state',
    () async {
      final outer = await Directory.systemTemp.createTemp(
        'ii_ffmpeg_universal_recovery_test_',
      );
      final outerMarker = File(p.join(outer.path, '.ii-disposable-owner'));
      final outerToken = 'ii-workspace-recovery-test-${outer.path}';
      await outerMarker.writeAsString(outerToken, flush: true);
      addTearDown(() async {
        if (await outerMarker.exists() &&
            await outerMarker.readAsString() == outerToken) {
          await outer.delete(recursive: true);
        }
      });

      final root = Directory(p.join(outer.path, 'workspaces'));
      final active = await IoWorkspace.create('active_parent', root: root);
      addTearDown(() async {
        if (await active.directory.exists()) await active.dispose();
      });
      final unrelated = Directory(
        p.join(root.path, 'ii_ffmpeg_universal_user_owned_fixture'),
      );
      await unrelated.create();
      await File(
        p.join(unrelated.path, '.ii-disposable-owner'),
      ).writeAsString(jsonEncode({'owner': 'different-owner'}), flush: true);

      final child = await Process.start('dart', [
        'run',
        'tool/workspace_crash_fixture.dart',
        root.path,
      ], workingDirectory: Directory.current.path);
      final childErrors = <String>[];
      child.stderr
          .transform(utf8.decoder)
          .listen((value) => childErrors.add(value));
      final childLine = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.startsWith('WORKSPACE='))
          .timeout(const Duration(seconds: 30));
      final childPath = childLine.substring('WORKSPACE='.length);
      expect(await Directory(childPath).exists(), isTrue);
      final workspaceRecord =
          jsonDecode(
                await File(
                  p.join(childPath, '.ii-disposable-owner'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final ownerPid = workspaceRecord['pid'];
      expect(ownerPid, isA<int>());
      expect(Process.killPid(ownerPid as int, ProcessSignal.sigkill), isTrue);
      await child.exitCode.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          child.kill(ProcessSignal.sigkill);
          throw StateError(
            'Killed workspace fixture did not exit: ${childErrors.join()}',
          );
        },
      );

      final publicationToken = List<String>.filled(48, 'b').join();
      final target = File(p.join(outer.path, 'published.bin'));
      await target.writeAsString('existing-user-output', flush: true);
      final partial = File('${target.path}.ii-$publicationToken.partial');
      await partial.writeAsBytes(List<int>.filled(1024 * 1024, 7), flush: true);
      await File(
        p.join(childPath, '.ii-publication-$publicationToken.json'),
      ).writeAsString(
        jsonEncode({
          'schema': 1,
          'owner': workspaceRecord['owner'],
          'root_token': workspaceRecord['root_token'],
          'workspace_token': workspaceRecord['token'],
          'workspace_id': p.basename(childPath),
          'token': publicationToken,
          'target_path': target.path,
          'partial_path': partial.path,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      final unjournaled = File(
        '${target.path}.ii-${List<String>.filled(48, 'c').join()}.partial',
      );
      await unjournaled.writeAsString('not-owned-by-a-journal', flush: true);

      final recovered = await IoWorkspace.recoverStale(
        root: root,
        minimumAge: Duration.zero,
      );
      expect(recovered, 1);
      expect(await Directory(childPath).exists(), isFalse);
      expect(await partial.exists(), isFalse);
      expect(await target.readAsString(), 'existing-user-output');
      expect(await unjournaled.readAsString(), 'not-owned-by-a-journal');
      expect(await active.directory.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);

      await active.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
