import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the API has bounded scale and per-instance concurrency', () {
    final server = File('bin/server.dart').readAsStringSync();

    expect(server, contains('maxInstances: const Instances(6)'));
    expect(server, contains('concurrency: const Concurrency(40)'));
  });

  test('the hosted app shell revalidates without disabling storage', () {
    final config =
        jsonDecode(File('../firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final hosting = config['hosting'] as Map<String, dynamic>;
    final headers = hosting['headers'] as List<dynamic>;
    const shellSources = <String>{
      '/',
      '/index.html',
      '/flutter_bootstrap.js',
      '/main.dart.js',
      '**',
    };

    for (final source in shellSources) {
      final rule = headers.cast<Map<String, dynamic>>().singleWhere(
        (candidate) => candidate['source'] == source,
      );
      final cacheControl =
          (rule['headers'] as List<dynamic>)
                  .cast<Map<String, dynamic>>()
                  .singleWhere(
                    (header) => header['key'] == 'Cache-Control',
                  )['value']
              as String;
      expect(cacheControl, contains('no-cache'), reason: source);
      expect(cacheControl, contains('must-revalidate'), reason: source);
      expect(cacheControl, isNot(contains('no-store')), reason: source);
    }
  });

  test('API responses remain non-cacheable', () {
    final support = File('lib/src/http_support.dart').readAsStringSync();

    expect(support, contains("'cache-control': 'no-store'"));
  });

  test('hosting does not cache the API routes it rewrites', () {
    // Firebase Hosting applies the LAST matching header rule, so the '**'
    // shell rule silently overrode the function's own 'no-store' until the
    // API routes were re-declared after it. Losing that ordering serves
    // authenticated API responses as revalidate-cacheable through the CDN.
    final config =
        jsonDecode(File('../firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final hosting = config['hosting'] as Map<String, dynamic>;
    final headers = hosting['headers'] as List<dynamic>;
    final sources = headers
        .cast<Map<String, dynamic>>()
        .map((rule) => rule['source'] as String)
        .toList();

    final rewrittenToFunction = hosting['rewrites'] as List<dynamic>;
    final apiSources = rewrittenToFunction
        .cast<Map<String, dynamic>>()
        .where((rewrite) => rewrite.containsKey('function'))
        .map((rewrite) => rewrite['source'] as String);

    for (final source in apiSources) {
      final index = sources.indexOf(source);
      expect(
        index,
        isNot(-1),
        reason:
            '$source is rewritten to a function but has no header rule, '
            "so the '**' rule decides its Cache-Control.",
      );
      expect(
        index,
        greaterThan(sources.indexOf('**')),
        reason: "$source must be declared after '**' to win precedence.",
      );
      final cacheControl =
          (headers.cast<Map<String, dynamic>>()[index]['headers']
                      as List<dynamic>)
                  .cast<Map<String, dynamic>>()
                  .singleWhere(
                    (header) => header['key'] == 'Cache-Control',
                  )['value']
              as String;
      expect(cacheControl, contains('no-store'), reason: source);
    }
  });
}
