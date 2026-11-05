import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/src/backends/io_workspace.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory owned;
  setUp(() async {
    owned = await Directory.systemTemp.createTemp('ii-root-security-test-');
    await File(p.join(owned.path, '.ii-test-owner')).writeAsString(owned.path);
  });
  tearDown(() async {
    final marker = File(p.join(owned.path, '.ii-test-owner'));
    if (await marker.readAsString() == owned.path) {
      await owned.delete(recursive: true);
    }
  });

  test('rejects unowned root before opening a linked root lock', () async {
    final root = await Directory(p.join(owned.path, 'root')).create();
    final canary = await File(
      p.join(owned.path, 'canary'),
    ).writeAsString('keep');
    await Link(p.join(root.path, '.ii-root-lock')).create(canary.path);
    await expectLater(IoWorkspace.recoverStale(root: root), throwsException);
    expect(await canary.readAsString(), 'keep');
  });

  test(
    'rejects a replaced root lock even in an otherwise owned root',
    () async {
      final root = Directory(p.join(owned.path, 'root'));
      final seed = await IoWorkspace.create('seed', root: root);
      await seed.dispose();
      final lock = File(p.join(root.path, '.ii-root-lock'));
      await lock.delete();
      final canary = await File(
        p.join(owned.path, 'canary'),
      ).writeAsString('keep');
      await Link(lock.path).create(canary.path);
      await expectLater(IoWorkspace.recoverStale(root: root), throwsException);
      expect(await canary.readAsString(), 'keep');
    },
  );

  test('locking an owned root preserves existing lock bytes', () async {
    final root = Directory(p.join(owned.path, 'root'));
    final seed = await IoWorkspace.create('seed', root: root);
    await seed.dispose();
    final lock = File(p.join(root.path, '.ii-root-lock'));
    await lock.writeAsString('keep');
    await IoWorkspace.recoverStale(root: root);
    expect(await lock.readAsString(), 'keep');
  });

  test('POSIX root locks are created with private permissions', () async {
    if (Platform.isWindows) return;
    final root = Directory(p.join(owned.path, 'root'));
    final seed = await IoWorkspace.create('seed', root: root);
    await seed.dispose();
    final lock = File(p.join(root.path, '.ii-root-lock'));
    expect((await lock.stat()).mode & 0x1ff, 0x180);
  });

  test(
    'recovery preserves linked workspace locks without opening them',
    () async {
      final root = Directory(p.join(owned.path, 'root'));
      final live = await IoWorkspace.create('seed', root: root);
      await live.dispose();
      final rootRecord =
          jsonDecode(
                await File(
                  p.join(root.path, '.ii-workspace-root-owner'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final stale = await Directory(
        p.join(root.path, 'ii_ffmpeg_universal_stale'),
      ).create();
      await File(p.join(stale.path, '.ii-disposable-owner')).writeAsString(
        jsonEncode({
          'owner': 'ii-ffmpeg-universal',
          'token': 'a' * 48,
          'root_token': rootRecord['token'],
          'workspace_id': p.basename(stale.path),
          'created_at': DateTime.fromMillisecondsSinceEpoch(
            0,
          ).toUtc().toIso8601String(),
          'pid': pid + 1000000,
        }),
      );
      final canary = await File(
        p.join(owned.path, 'canary'),
      ).writeAsString('keep');
      await Link(p.join(stale.path, '.ii-active-lock')).create(canary.path);
      expect(
        await IoWorkspace.recoverStale(root: root, minimumAge: Duration.zero),
        0,
      );
      expect(await canary.readAsString(), 'keep');
      expect(await stale.exists(), isTrue);
    },
  );
}
