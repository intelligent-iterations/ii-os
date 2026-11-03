import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:path/path.dart' as p;

void main() {
  late _BundleFixture fixture;

  setUp(() async {
    fixture = await _BundleFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('loads one exact regular attested desktop closure', () async {
    final bundle = await loadAttestedFfmpegDesktopBundle(
      rootPath: fixture.root.path,
      manifestSha256: fixture.manifestSha256,
    );

    expect(bundle.ffmpegPath, p.join(fixture.root.path, 'ffmpeg'));
    expect(bundle.ffprobePath, p.join(fixture.root.path, 'ffprobe'));
    expect(bundle.dynamicLibraries, isEmpty);
  });

  test('rejects an unattested manifest', () async {
    await expectLater(
      loadAttestedFfmpegDesktopBundle(
        rootPath: fixture.root.path,
        manifestSha256: '0' * 64,
      ),
      throwsFormatException,
    );
  });

  test('rejects a linked executable', () async {
    final executable = File(p.join(fixture.root.path, 'ffmpeg'));
    final external = File(
      p.join(fixture.root.parent.path, '${fixture.owner}.bin'),
    );
    await external.writeAsBytes([1, 2, 3]);
    fixture.external = external;
    await executable.delete();
    await Link(executable.path).create(external.path);

    await expectLater(
      loadAttestedFfmpegDesktopBundle(
        rootPath: fixture.root.path,
        manifestSha256: fixture.manifestSha256,
      ),
      throwsFormatException,
    );
  });

  test('rejects a closure identity mismatch', () async {
    final manifest =
        jsonDecode(
              await File(
                p.join(fixture.root.path, 'manifest.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    manifest['closure_sha256'] = 'f' * 64;
    final bytes = utf8.encode(jsonEncode(manifest));
    await File(p.join(fixture.root.path, 'manifest.json')).writeAsBytes(bytes);

    await expectLater(
      loadAttestedFfmpegDesktopBundle(
        rootPath: fixture.root.path,
        manifestSha256: sha256.convert(bytes).toString(),
      ),
      throwsFormatException,
    );
  });

  test('rejects a desktop closure for another CPU architecture', () async {
    final manifestFile = File(p.join(fixture.root.path, 'manifest.json'));
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    manifest['architecture'] = _architecture == 'arm64' ? 'x86_64' : 'arm64';
    final bytes = utf8.encode(jsonEncode(manifest));
    await manifestFile.writeAsBytes(bytes);

    await expectLater(
      loadAttestedFfmpegDesktopBundle(
        rootPath: fixture.root.path,
        manifestSha256: sha256.convert(bytes).toString(),
      ),
      throwsFormatException,
    );
  });
}

final class _BundleFixture {
  _BundleFixture(this.root, this.owner, this.manifestSha256);

  final Directory root;
  final String owner;
  final String manifestSha256;
  File? external;

  static Future<_BundleFixture> create() async {
    final owner =
        'ii-ffmpeg-loader-test-${DateTime.now().microsecondsSinceEpoch}-$pid';
    final root = await Directory.systemTemp.createTemp('$owner-');
    await File(p.join(root.path, '.ii-disposable-owner')).writeAsString(owner);
    final artifacts = <Map<String, Object?>>[];
    for (final (name, role, bytes) in <(String, String, List<int>)>[
      ('ffmpeg', 'ffmpeg', [1, 2, 3]),
      ('ffprobe', 'ffprobe', [4, 5, 6]),
    ]) {
      final file = File(p.join(root.path, name));
      await file.writeAsBytes(bytes);
      artifacts.add({
        'name': name,
        'role': role,
        'architecture': _architecture,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    final manifest = {
      'schema': 1,
      'platform': Platform.operatingSystem,
      'architecture': _architecture,
      'engine_version': 'n8.1.2',
      'closure_sha256': sha256
          .convert(
            utf8.encode(
              jsonEncode(
                artifacts
                    .map(
                      (value) => {
                        'architecture': value['architecture'],
                        'name': value['name'],
                        'role': value['role'],
                        'sha256': value['sha256'],
                      },
                    )
                    .toList(),
              ),
            ),
          )
          .toString(),
      'artifacts': artifacts,
    };
    final bytes = utf8.encode(jsonEncode(manifest));
    await File(p.join(root.path, 'manifest.json')).writeAsBytes(bytes);
    return _BundleFixture(root, owner, sha256.convert(bytes).toString());
  }

  Future<void> dispose() async {
    final marker = File(p.join(root.path, '.ii-disposable-owner'));
    if (!await marker.exists() || await marker.readAsString() != owner) {
      throw StateError('Refusing to remove an unowned desktop fixture.');
    }
    await root.delete(recursive: true);
    final retained = external;
    if (retained != null && await retained.exists()) {
      if (p.basename(retained.path) != '$owner.bin') {
        throw StateError('Refusing to remove an unowned external fixture.');
      }
      await retained.delete();
    }
  }
}

final String _architecture = switch (Abi.current()) {
  Abi.linuxArm64 || Abi.macosArm64 => 'arm64',
  Abi.linuxX64 || Abi.macosX64 => 'x86_64',
  _ => 'unsupported',
};
