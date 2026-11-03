import 'dart:convert';

/// Deployment-owned executable sources accepted by the agent security gate.
///
/// The reusable package defines and validates the contract but deliberately
/// ships no repository paths or reviewed blob identities. A deployment passes
/// a base64-encoded JSON manifest at its composition root. An empty value
/// disables agent readiness rather than trusting an empty source set.
final class AgentTrustedSourceManifest {
  AgentTrustedSourceManifest._({
    required Map<String, String> blobShas,
    required Set<String> executablePaths,
    required Map<String, Set<String>> pythonImportNamespaces,
  }) : blobShas = Map.unmodifiable(blobShas),
       executablePaths = Set.unmodifiable(executablePaths),
       pythonImportNamespaces = Map.unmodifiable({
         for (final entry in pythonImportNamespaces.entries)
           entry.key: Set.unmodifiable(entry.value),
       });

  const AgentTrustedSourceManifest.disabled()
    : blobShas = const {},
      executablePaths = const {},
      pythonImportNamespaces = const {};

  factory AgentTrustedSourceManifest.fromBase64(String encoded) {
    final value = encoded.trim();
    if (value.isEmpty) return const AgentTrustedSourceManifest.disabled();
    final decoded = jsonDecode(utf8.decode(base64Decode(value)));
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(const {
          'schema_version',
          'blob_shas',
          'executable_paths',
          'python_import_namespaces',
        }).isNotEmpty ||
        decoded['schema_version'] != 1) {
      throw const FormatException('Invalid agent source manifest envelope.');
    }
    final blobShas = _stringMap(decoded['blob_shas'], 'blob_shas');
    final executablePaths = _stringSet(
      decoded['executable_paths'],
      'executable_paths',
    );
    final rawNamespaces = decoded['python_import_namespaces'];
    if (rawNamespaces is! Map<String, Object?>) {
      throw const FormatException(
        'python_import_namespaces must be an object.',
      );
    }
    final namespaces = {
      for (final entry in rawNamespaces.entries)
        entry.key: _stringSet(entry.value, entry.key),
    };
    if (blobShas.isEmpty ||
        blobShas.keys.any((path) => !_safePath(path)) ||
        blobShas.values.any(
          (sha) => !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha),
        ) ||
        !blobShas.keys.toSet().containsAll(executablePaths) ||
        namespaces.keys.any((path) => !_safePath(path))) {
      throw const FormatException('Invalid agent source manifest values.');
    }
    final reviewedPythonPaths = blobShas.keys
        .where((path) => path.endsWith('.py'))
        .toSet();
    final namespacedPythonPaths = {
      for (final entry in namespaces.entries)
        for (final name in entry.value) '${entry.key}/$name',
    };
    if (reviewedPythonPaths.length != namespacedPythonPaths.length ||
        !reviewedPythonPaths.containsAll(namespacedPythonPaths)) {
      throw const FormatException(
        'Python namespaces must cover every reviewed Python source exactly.',
      );
    }
    return AgentTrustedSourceManifest._(
      blobShas: blobShas,
      executablePaths: executablePaths,
      pythonImportNamespaces: namespaces,
    );
  }

  final Map<String, String> blobShas;
  final Set<String> executablePaths;
  final Map<String, Set<String>> pythonImportNamespaces;

  bool get configured => blobShas.isNotEmpty;

  List<String> get sourcePaths => blobShas.keys.toList(growable: false);

  Map<String, String> get modes => {
    for (final path in blobShas.keys)
      path: executablePaths.contains(path) ? '100755' : '100644',
  };
}

Map<String, String> _stringMap(Object? value, String label) {
  if (value is! Map<String, Object?> ||
      value.values.any((item) => item is! String)) {
    throw FormatException('$label must contain only string values.');
  }
  return value.map((key, value) => MapEntry(key, value! as String));
}

Set<String> _stringSet(Object? value, String label) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$label must contain only strings.');
  }
  final result = value.cast<String>().toSet();
  if (result.length != value.length || result.any((item) => item.isEmpty)) {
    throw FormatException('$label contains an empty or duplicate value.');
  }
  return result;
}

bool _safePath(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.contains('\\') &&
    !path.split('/').contains('..') &&
    !path.split('/').contains('.');
