import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('provider SDK imports are adapters or recorded migration debt', () {
    final repository = Directory.current.parent;
    final actual = <String>{};
    for (final relativeRoot in const [
      'lib',
      'functions/lib',
      'functions/bin',
    ]) {
      final root = Directory('${repository.path}/$relativeRoot');
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = _relative(repository, entity);
        if (_isAdapter(relative)) continue;
        for (final line in entity.readAsLinesSync()) {
          final match = RegExp(
            r"^import 'package:([^/']+)",
          ).firstMatch(line.trim());
          final package = match?.group(1);
          if (package != null && _isProviderPackage(package)) {
            actual.add('$relative|$package');
          }
        }
      }
    }

    final baselineFile = File(
      '${repository.path}/tool/provider_coupling_baseline.txt',
    );
    expect(
      baselineFile.existsSync(),
      isTrue,
      reason: 'The provider-coupling migration ledger is required.',
    );
    final baseline = baselineFile
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet();
    final additions = actual.difference(baseline).toList()..sort();
    final stale = baseline.difference(actual).toList()..sort();

    expect(
      additions,
      isEmpty,
      reason:
          'New provider SDK imports belong under a providers/<name>/ adapter.',
    );
    expect(
      stale,
      isEmpty,
      reason:
          'Remove resolved entries so the provider-coupling baseline only shrinks.',
    );
  });
}

bool _isAdapter(String path) =>
    path.startsWith('lib/providers/') ||
    path.startsWith('functions/lib/src/providers/');

bool _isProviderPackage(String package) =>
    package.startsWith('firebase') ||
    package == 'google_cloud_firestore' ||
    package == 'googleapis' ||
    package == 'googleapis_auth' ||
    package == 'appwrite' ||
    package == 'supabase' ||
    package == 'supabase_flutter' ||
    package == 'github' ||
    package == 'octokit' ||
    package == 'minio' ||
    package.startsWith('aws_') ||
    package.startsWith('amplify_');

String _relative(Directory repository, File file) => file.path
    .substring(repository.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');
