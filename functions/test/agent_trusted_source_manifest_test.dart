import 'dart:convert';

import 'package:ii_os_functions/src/agent_trusted_source_manifest.dart';
import 'package:test/test.dart';

void main() {
  test('empty configuration disables trusted agent execution', () {
    const manifest = AgentTrustedSourceManifest.disabled();

    expect(manifest.configured, isFalse);
    expect(manifest.sourcePaths, isEmpty);
    expect(manifest.modes, isEmpty);
  });

  test('deployment manifest validates paths, hashes, modes, and imports', () {
    final manifest = AgentTrustedSourceManifest.fromBase64(
      _encode({
        'schema_version': 1,
        'blob_shas': {
          '.github/workflows/agent.yml': 'a' * 40,
          'automation/helper.py': 'b' * 40,
          'automation/run.sh': 'c' * 40,
        },
        'executable_paths': ['automation/run.sh'],
        'python_import_namespaces': {
          'automation': ['helper.py'],
        },
      }),
    );

    expect(manifest.configured, isTrue);
    expect(manifest.modes['automation/helper.py'], '100644');
    expect(manifest.modes['automation/run.sh'], '100755');
  });

  test('unreviewed Python namespace shape fails closed', () {
    expect(
      () => AgentTrustedSourceManifest.fromBase64(
        _encode({
          'schema_version': 1,
          'blob_shas': {'automation/helper.py': 'b' * 40},
          'executable_paths': <String>[],
          'python_import_namespaces': <String, Object?>{},
        }),
      ),
      throwsFormatException,
    );
  });
}

String _encode(Map<String, Object?> value) =>
    base64Encode(utf8.encode(jsonEncode(value)));
