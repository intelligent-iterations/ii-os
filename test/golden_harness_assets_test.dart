import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The golden harnesses load fonts by literal path, and golden tests are
/// excluded from CI because they are tied to the platform that rendered them.
/// Those two facts together are how the harnesses stayed broken for days: when
/// the product moved from Inter to Manrope the files they named stopped
/// existing, every golden threw in `setUpAll`, and the suite that gates
/// merges never ran them to notice.
///
/// These assertions live in the gating suite on purpose. They do not compare
/// pixels, so they run everywhere, and they fail the moment a harness names an
/// asset the package no longer ships.
void main() {
  const harnesses = ['test/golden_harness.dart', 'test/page_golden_harness.dart'];
  const packageRoot = 'packages/ii_os_design_system';

  /// `Manrope-$weight.ttf` in a harness, `- asset: fonts/...` in the pubspec.
  final harnessFont = RegExp(
    r"rootBundle\.load\(\s*'packages/ii_os_design_system/(fonts/[A-Za-z0-9-]+)"
    r"\$\{?weight\}?(\.ttf)'",
  );
  final harnessWeights = RegExp(r"for \(final weight in \[([^\]]*)\]\)");
  final pubspecAsset = RegExp(r'asset:\s*(fonts/[^\s]+\.ttf)');

  Set<String> declaredAssets() => pubspecAsset
      .allMatches(File('$packageRoot/pubspec.yaml').readAsStringSync())
      .map((match) => match.group(1)!)
      .toSet();

  for (final harness in harnesses) {
    test('$harness loads fonts that exist', () {
      final source = File(harness).readAsStringSync();
      final weights = harnessWeights
          .firstMatch(source)
          ?.group(1)
          ?.split(',')
          .map((weight) => weight.trim().replaceAll("'", ''))
          .where((weight) => weight.isNotEmpty)
          .toList();
      expect(
        weights,
        isNotNull,
        reason: '$harness no longer lists font weights in a readable form; '
            'this test can no longer prove what it loads exists',
      );

      final template = harnessFont.firstMatch(source);
      expect(
        template,
        isNotNull,
        reason: '$harness no longer loads a design system font by the shape '
            'this test understands',
      );

      final declared = declaredAssets();
      for (final weight in weights!) {
        final asset = '${template!.group(1)}$weight${template.group(2)}';
        expect(
          File('$packageRoot/$asset').existsSync(),
          isTrue,
          reason: '$harness loads $asset, which the design system does not '
              'ship. Every golden fails in setUpAll when this drifts, and CI '
              'excludes goldens so nothing else will tell you.',
        );
        expect(
          declared,
          contains(asset),
          reason: '$asset exists but the design system pubspec does not '
              'declare it, so it is not bundled into a real build',
        );
      }
    });
  }

  test('the harnesses cover every weight the design system ships', () {
    final declared = declaredAssets();
    final loaded = <String>{};
    for (final harness in harnesses) {
      final source = File(harness).readAsStringSync();
      final template = harnessFont.firstMatch(source);
      final weights = harnessWeights.firstMatch(source)?.group(1);
      if (template == null || weights == null) continue;
      for (final weight in weights.split(',')) {
        final trimmed = weight.trim().replaceAll("'", '');
        if (trimmed.isEmpty) continue;
        loaded.add('${template.group(1)}$trimmed${template.group(2)}');
      }
    }
    expect(
      loaded,
      containsAll(declared),
      reason: 'a weight the product ships but the goldens never load renders '
          'as a substituted face in every golden, which is exactly the '
          'difference goldens exist to catch',
    );
  });
}
