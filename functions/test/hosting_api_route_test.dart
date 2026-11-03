import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Hosting must send every `/api/...` path to the control-plane function.
///
/// The browser calls the API as `/api?route=...`, so an `/api` rewrite alone
/// looks correct in the product while every path-style caller silently gets the
/// single-page app instead. Firebase Hosting answers those with HTTP 200 and an
/// HTML body, so a caller that checks the status code before parsing JSON reads
/// a success and then fails on the parse. That is exactly how the GitHub
/// workflow callbacks failed: they POST to `/api/v1/...` and received the SPA.
void main() {
  test('hosting routes both API call styles to the function', () {
    final config =
        jsonDecode(File('../firebase.json').readAsStringSync())
            as Map<String, Object?>;
    final hosting = config['hosting'];
    final site = (hosting is List ? hosting.first : hosting) as Map;
    final rewrites = (site['rewrites'] as List).cast<Map<String, Object?>>();

    Map<String, Object?>? rewriteFor(String source) => rewrites
        .where((rewrite) => rewrite['source'] == source)
        .cast<Map<String, Object?>?>()
        .firstWhere((rewrite) => true, orElse: () => null);

    for (final source in const ['/api', '/api/**']) {
      final rewrite = rewriteFor(source);
      expect(
        rewrite,
        isNotNull,
        reason:
            'without a $source rewrite, callers of that shape receive the '
            'single-page app with HTTP 200 instead of the API',
      );
      expect((rewrite!['function'] as Map)['functionId'], 'api');
    }

    final catchAll = rewrites.indexWhere(
      (rewrite) => rewrite['source'] == '**',
    );
    final apiPaths = rewrites.indexWhere(
      (rewrite) => rewrite['source'] == '/api/**',
    );
    expect(
      apiPaths,
      lessThan(catchAll),
      reason: 'the single-page app catch-all must not shadow the API',
    );
  });
}
