import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/agent_trusted_source_manifest.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The copyable agent kit must satisfy the same contracts this backend
/// enforces when it dispatches and verifies agent workflows. These checks run
/// the backend's own readiness functions against the kit files.
const _kit = '../examples/implementation';
const _workflows = '$_kit/.github/workflows';

String _read(String path) => File(path).readAsStringSync();

Map<String, Object?> _yaml(String path) =>
    _plain(loadYaml(_read(path))) as Map<String, Object?>;

Object? _plain(Object? value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _plain(entry.value),
    };
  }
  if (value is YamlList) return value.map(_plain).toList();
  return value;
}

const _agentWorkflows = [
  iiOsAgentTaskWorkflow,
  iiOsAgentWorkTicketWorkflow,
  iiOsCodexAuthWorkflow,
  iiOsCodexAuthFinalizeWorkflow,
  iiOsAgentPermissionInstallerWorkflow,
  iiOsAgentPermissionInstallerImplWorkflow,
];

/// Inputs the backend sends on each dispatch (agent_ticket_dispatcher.dart,
/// api_codex_auth_route.dart, workflow_codex_verification.dart,
/// api_agent_permission_routes.dart).
const _ticketInputs = {
  'repository',
  'issue_number',
  'permission_profile',
  'permission_ref',
  'permission_digest',
  'project_item_id',
  'dispatch_id',
  'workspace_id',
  'codex_secret_digest',
  'trusted_source_sha',
};
const _codexAuthInputs = {
  'operation',
  'repository',
  'codex_auth_session_id',
  'codex_auth_nonce',
  'codex_auth_reauthenticate',
};
const _permissionInputs = {
  'profile_id',
  'profile_version',
  'profile_digest',
  'profile_json',
  'workspace_id',
  'approval_id',
  'dispatch_id',
  'dispatch_fence',
};

Map<String, Object?> _jobs(Map<String, Object?> workflow) =>
    (workflow['jobs']! as Map).cast<String, Object?>();

String _gitBlobSha(List<int> bytes) => sha1.convert([
  ...utf8.encode('blob ${bytes.length}\u0000'),
  ...bytes,
]).toString();

void main() {
  test('kit gateway and work-ticket body pass the broker security check', () {
    final check = agentWorkflowEnvironmentCheck(
      _read('$_workflows/$iiOsAgentTaskWorkflow'),
      workTicketSource: _read('$_workflows/$iiOsAgentWorkTicketWorkflow'),
      repository: 'acme-co/example-app',
    );
    expect(check['status'], 'passed', reason: '${check['detail']}');
  });

  test('gateway accepts every input the backend dispatches', () {
    final workflow = _yaml('$_workflows/$iiOsAgentTaskWorkflow');
    final on = (workflow['on']! as Map).cast<String, Object?>();
    expect(on.keys.toSet(), {'workflow_dispatch', 'workflow_call'});
    final inputs = ((on['workflow_dispatch']! as Map)['inputs']! as Map).keys
        .toSet();
    expect(inputs, containsAll(_ticketInputs));
    expect(inputs, containsAll(_codexAuthInputs));
    final operation =
        ((on['workflow_dispatch']! as Map)['inputs']! as Map)['operation'];
    expect((operation as Map)['options'], [
      'work_ticket',
      'codex_auth',
      'codex_auth_verify',
    ]);
    // The backend binds a dispatched ticket to its run by this exact title.
    expect(
      workflow['run-name'],
      contains(
        "format('ii-os agent / {0}#{1} / {2}', inputs.repository, "
        'inputs.issue_number, inputs.dispatch_id)',
      ),
    );
  });

  test('permission installer surface matches the backend dispatch', () {
    final workflow = _yaml('$_workflows/$iiOsAgentPermissionInstallerWorkflow');
    final on = (workflow['on']! as Map).cast<String, Object?>();
    expect(on.keys.toSet(), {'workflow_dispatch'});
    expect(
      ((on['workflow_dispatch']! as Map)['inputs']! as Map).keys.toSet(),
      _permissionInputs,
    );
    expect(
      workflow['run-name'],
      r'ii-os permission v4 / ${{ inputs.approval_id }} / '
      r'${{ inputs.dispatch_id }} / ${{ inputs.profile_id }}@'
      r'${{ inputs.profile_version }} / ${{ inputs.profile_digest }} / '
      r'bootstrap@${{ github.sha }}',
    );
    final install = (_jobs(workflow)['install']! as Map)
        .cast<String, Object?>();
    // The backend accepts this installer only through the coordinator body
    // pinned at an exact commit.
    expect(
      install['uses'],
      matches(
        RegExp(
          r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/'
          '${RegExp.escape(iiOsAgentPermissionInstallerImplWorkflow)}'
          r'@[0-9a-f]{40}$',
        ),
      ),
    );
  });

  test('every agent job is bound, bounded and least-privileged', () {
    for (final name in _agentWorkflows) {
      final workflow = _yaml('$_workflows/$name');
      expect(workflow['permissions'], <String, Object?>{}, reason: name);
      for (final entry in _jobs(workflow).entries) {
        final job = (entry.value! as Map).cast<String, Object?>();
        final where = '$name#${entry.key}';
        if (job.containsKey('uses')) {
          expect(job['secrets'], 'inherit', reason: where);
          continue;
        }
        expect(
          job['runs-on'],
          r'${{ fromJSON(vars.II_OS_AGENT_RUNS_ON) }}',
          reason: where,
        );
        expect(job['timeout-minutes'], isA<int>(), reason: where);
        expect(
          job['environment'],
          name == iiOsAgentPermissionInstallerImplWorkflow
              ? iiOsAgentBootstrapEnvironment
              : iiOsAgentEnvironment,
          reason: where,
        );
        final permissions = (job['permissions']! as Map)
            .cast<String, Object?>();
        expect(permissions, {
          'contents': 'read',
          'id-token': 'write',
        }, reason: where);
        final steps = (job['steps']! as List).cast<Map<Object?, Object?>>();
        expect(
          steps.first['name'],
          'Require the agent kit settings',
          reason: where,
        );
        final settings = steps.first['run']! as String;
        for (final setting in [
          'II_OS_CONNECTOR_URL',
          'II_OS_AGENT_HOST_ID',
          'II_OS_AGENT_STATE_DIR',
          'II_OS_GITHUB_APP_ID',
          'II_OS_GITHUB_APP_SLUG',
        ]) {
          expect(settings, contains(setting), reason: where);
        }
      }
    }
  });

  test('kit workflows stay inert, pinned and free of paid features', () {
    final pinned = RegExp(r'^[^@\s]+@[0-9a-f]{40}\s+#\s*\S+');
    for (final name in _agentWorkflows) {
      final text = _read('$_workflows/$name');
      // Only ii-os starts these workflows; nothing triggers them implicitly.
      expect(
        {'workflow_dispatch', 'workflow_call'},
        containsAll((_yaml('$_workflows/$name')['on']! as Map).keys),
        reason: name,
      );
      for (final forbidden in [
        'self-hosted',
        'upload-artifact',
        'actions/cache',
        'II'
            'F_', // the private orchestration prefix
      ]) {
        expect(text, isNot(contains(forbidden)), reason: '$name: $forbidden');
      }
      for (final line in const LineSplitter().convert(text)) {
        final match = RegExp(r'^\s*(?:-\s+)?uses:\s*(.+)$').firstMatch(line);
        if (match == null) continue;
        final target = match.group(1)!.trim();
        if (target.startsWith('./')) continue;
        expect(
          pinned.hasMatch(target) || target.contains('/.github/workflows/'),
          isTrue,
          reason: '$name: $line',
        );
      }
    }
  });

  test('immutable trusted tags are verified inside the reviewed bodies', () {
    expect(
      _read('$_workflows/$iiOsAgentWorkTicketWorkflow'),
      contains(r'refs/tags/ii-os-agent-v4-${TRUSTED_SOURCE_SHA}'),
    );
    for (final name in [iiOsCodexAuthWorkflow, iiOsCodexAuthFinalizeWorkflow]) {
      expect(
        _read('$_workflows/$name'),
        contains(r'refs/tags/ii-os-agent-v4-${GITHUB_SHA}'),
        reason: name,
      );
    }
    expect(
      _read('$_workflows/$iiOsAgentPermissionInstallerImplWorkflow'),
      contains(r'refs/tags/ii-os-agent-v4-bootstrap-${GITHUB_SHA}'),
    );
  });

  test('generated trusted-source manifest is valid for the kit sources', () {
    // The manifest is deployment-owned; the kit ships only its generator.
    final generated = Process.runSync(
      'python3',
      ['scripts/agent_kit_manifest.py', 'trusted-sources'],
      workingDirectory: _kit,
      environment: {'PYTHONDONTWRITEBYTECODE': '1'},
    );
    expect(generated.exitCode, 0, reason: '${generated.stderr}');
    final encoded = base64Encode(utf8.encode(generated.stdout as String));
    final manifest = AgentTrustedSourceManifest.fromBase64(encoded);
    expect(manifest.configured, isTrue);
    for (final name in _agentWorkflows) {
      expect(manifest.blobShas.keys, contains('.github/workflows/$name'));
    }
    for (final entry in manifest.blobShas.entries) {
      final file = File('$_kit/${entry.key}');
      expect(
        _gitBlobSha(file.readAsBytesSync()),
        entry.value,
        reason: '${entry.key} changed; regenerate the manifest',
      );
      final executable = file.statSync().mode & 0x40 != 0;
      expect(
        manifest.executablePaths.contains(entry.key),
        executable,
        reason: '${entry.key} executable bit',
      );
    }
    // Emulate the backend's import-namespace gate over what git will commit.
    final listed = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      '.',
    ], workingDirectory: _kit);
    expect(listed.exitCode, 0, reason: '${listed.stderr}');
    final tracked = const LineSplitter()
        .convert(listed.stdout as String)
        .where((path) => File('$_kit/$path').existsSync())
        .toSet();
    for (final directory in manifest.pythonImportNamespaces.keys) {
      final prefix = '$directory/';
      final children = <String, String>{};
      for (final path in tracked.where((path) => path.startsWith(prefix))) {
        final rest = path.substring(prefix.length);
        final slash = rest.indexOf('/');
        children[slash < 0 ? rest : rest.substring(0, slash)] = slash < 0
            ? 'blob'
            : 'tree';
      }
      final reviewed = {
        for (final child in manifest.pythonImportNamespaces.keys)
          if (child.startsWith(prefix) &&
              !child.substring(prefix.length).contains('/'))
            child.substring(prefix.length),
      };
      final entries = <String>{
        for (final child in children.entries)
          if (pythonImportCandidate({
            'name': child.key,
            'type': child.value,
            'mode': child.value == 'tree' ? '040000' : '100644',
          }, reviewedDirectories: reviewed))
            pythonImportEntryIdentity({
              'name': child.key,
              'type': child.value,
              'mode': child.value == 'tree' ? '040000' : '100644',
            }),
      };
      expect(
        entries,
        manifest.pythonImportNamespaces[directory],
        reason: directory,
      );
    }
  });
}
