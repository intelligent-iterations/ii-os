import 'dart:io';

import 'package:test/test.dart';

/// The engine catalog defaults to Codex-only so tests stay terse. A
/// production call that forgets it would silently refuse a local engine the
/// deployment configured, so every production use must name it.
void main() {
  const policyCalls = [
    'AgentPermissionProfile.parse(',
    'requireExecutableAgentProfile(',
    'agentPermissionProfileFromListing(',
    'executableAgentPermissionProfileFromListings(',
    'agentProfileChecks(',
    'agentCapabilitiesForEngine(',
    'approvedAgentActivationClaim(',
    'AgentActivationStore(',
  ];
  final definitions = RegExp(
    r'(?:^|\n)\s*(?:void|bool|Set<String>|AgentPermissionProfile\??|'
    r'AgentActivationClaim\?|List<Map<String, Object\?>>|factory)\s+'
    r'[\w.]*\($|^\s*AgentActivationStore\($',
  );

  Iterable<File> productionSources() => [
    for (final root in ['lib', 'bin'])
      ...Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
  ];

  String argumentsAt(String source, int open) {
    var depth = 0;
    for (var index = open; index < source.length; index++) {
      if (source[index] == '(') depth++;
      if (source[index] == ')' && --depth == 0) {
        return source.substring(open, index + 1);
      }
    }
    throw StateError('unbalanced call');
  }

  test('every production engine-policy call names the deployment catalog', () {
    final missing = <String>[];
    for (final file in productionSources()) {
      final source = file.readAsStringSync();
      for (final call in policyCalls) {
        var start = source.indexOf(call);
        while (start >= 0) {
          final open = start + call.length - 1;
          final lineStart = source.lastIndexOf('\n', start) + 1;
          final prefix = source.substring(lineStart, open + 1);
          final isDefinition = definitions.hasMatch(prefix);
          if (!isDefinition && !argumentsAt(source, open).contains('engines')) {
            final line = '\n'.allMatches(source.substring(0, start)).length + 1;
            missing.add('${file.path}:$line $call');
          }
          start = source.indexOf(call, start + call.length);
        }
      }
      if (RegExp(
        r'\.map\(agentPermissionProfileFromListing\)',
      ).hasMatch(source)) {
        missing.add(
          '${file.path}: tear-off of agentPermissionProfileFromListing',
        );
      }
    }
    expect(missing, isEmpty);
  });

  test('the composition root hands its catalog to every agent surface', () {
    final server = File('bin/server.dart').readAsStringSync();

    expect(
      server,
      matches(
        RegExp(
          r"defineString\(\s*'II_OS_LOCAL_AGENT_ENGINES_BASE64',\s*"
          r"const ParamOptions\(defaultValue: ''\),?\s*\)",
        ),
      ),
    );
    expect(
      server,
      matches(
        RegExp(
          r'AgentEngineCatalog\.fromBase64\(\s*localAgentEngines\.value\(\),?\s*\)',
        ),
      ),
    );
    final clients = RegExp(r'GitHubClient\(').allMatches(server).length;
    final configured = RegExp(
      r'GitHubClient\([^;]*?agentEngines: agentEngines',
      dotAll: true,
    ).allMatches(server).length;
    expect(clients, greaterThan(0));
    expect(configured, clients);
  });
}
