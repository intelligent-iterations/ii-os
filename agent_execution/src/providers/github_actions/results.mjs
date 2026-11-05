import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdtempSync, openSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { readWorkerFile, workerSession, writeWorkerFile } from '../agent_runtime/files.mjs';
import { exactlyOne } from './prompt.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const quote = value => "'" + String(value).replaceAll("'", "'\"'\"'") + "'";
function durable(path, bytes) {
  const fd = openSync(path, 'wx', 0o600);
  try { writeFileSync(fd, bytes); fsyncSync(fd); } finally { closeSync(fd); }
}
function trustedSource(value) {
  const fd = openSync(value.path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 || (stat.mode & 0o022) || stat.size > 524288) throw Error('result-helper-integrity');
    const source = readFileSync(fd);
    if (source.length !== stat.size || hash(source) !== value.sha256) throw Error('result-helper-integrity');
    return source.toString('utf8');
  } finally { closeSync(fd); }
}

/** Reuse the reviewed result/QA policy and Git materializer, after the harness exits. */
export function createExistingResultCollector({ runtime, parent, task, helpers, readTelemetry }) {
  const stat = lstatSync(parent);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) || realpathSync(parent) !== parent || typeof readTelemetry !== 'function') throw Error('result-collector-binding-invalid');
  let used = false;
  return {
    async collect({ worker, execution, record, deadlineMs, signal }) {
      if (used) throw Error('result-collector-already-used'); used = true;
      if (record.inputs.environment.II_OS_WORK_TICKET !== runtime.canonicalJson(task) ||
          task.repository !== record.inputs.configuration.source.repository || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(task.repository ?? '') ||
          !['repositoryId', 'issueNumber'].every(key => Number.isSafeInteger(task[key]) && task[key] > 0) ||
          !['dispatchId', 'projectItemId'].every(key => /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(task[key] ?? '')) ||
          !/^[a-f0-9]{64}$/.test(task.promptDigest ?? '') || !/^[A-Za-z0-9][A-Za-z0-9-]{0,99}$/.test(task.appSlug ?? '') ||
          !/^\/[A-Za-z0-9/_-]+$/.test(worker.workspace) || !Number.isSafeInteger(execution.exitCode)) throw Error('result-collector-input-mismatch');
      const sources = {};
      for (const name of ['core', 'status', 'execute', 'materializer']) {
        const helper = helpers?.[name];
        if (!helper || !record.inputs.components.some(component => component.name === 'result-helper-' + name && component.version === 'sha256:' + helper.sha256)) throw Error('result-helper-unapproved');
        sources[name] = trustedSource(helper);
      }
      const marker = '\ncodex_failure_diagnostic() {';
      // The existing helpers' result path or the public kit's neutral one.
      const resultPlaceholder = exactlyOne(sources.status, ["'/iif/job/artifacts/ii-os-agent-result.json'", "'/ii-os-agent/artifacts/ii-os-agent-result.json'"]);
      if (sources.execute.split(marker).length !== 2 || !resultPlaceholder) throw Error('result-policy-version-unsupported');
      const policy = sources.execute.slice(sources.execute.indexOf(marker) + 1);
      const telemetry = readTelemetry();
      if (telemetry.executionId !== record.executionId || telemetry.attemptId !== record.attemptId || telemetry.inputDigest !== record.inputDigest || !telemetry.captureComplete) throw Error('result-telemetry-unconfirmed');
      const owner = randomUUID(), work = worker.workspace + '/ii-os-result-' + owner;
      const context = () => ({ timeoutMs: Math.min(120000, deadlineMs - Date.now()), signal });
      await worker.run({ command: '/usr/bin/python3', args: ['-c', 'import os,sys;os.mkdir(sys.argv[1],0o700)', work], ...context(), maxOutputBytes: 4096 });
      await writeWorkerFile(worker, work + '/codex.jsonl', Buffer.from(telemetry.transcript), context());
      const main = record.inputs.repositories.find(value => value.repository === task.repository);
      const [repositoryOwner, repositoryName] = task.repository.split('/');
      if (!main || !/^[a-f0-9]{40}$/.test(main.commit)) throw Error('result-source-unconfirmed');
      const globals = {
        owner: repositoryOwner, repo: repositoryName, issue_number: task.issueNumber, title: task.title ?? '',
        issue_url: `https://github.com/${task.repository}/issues/${task.issueNumber}`, stream_id: record.executionId,
        work_root: work, repo_dir: worker.workspace + '/repository', branch: 'ii-os-agent/' + hash(task.dispatchId).slice(0, 32), base_branch: 'dev',
        work_start_sha: main.commit, base_sha: main.commit, expected_old_head_sha: '',
        codex_log: work + '/codex.jsonl', codex_status: execution.exitCode, prompt_sha: task.promptDigest,
        git_user_name: task.gitName ?? 'ii-os-agent', git_user_email: task.gitEmail ?? 'agent@example.invalid',
        offline_issue_json: '', push_changes: '1', open_pr: '1', change_bundle: work + '/change.bundle',
        submodule_path: '', submodule_repository: '', submodule_repository_id: '', submodule_base_sha: '', submodule_expected_old_head_sha: '',
        deferred_comments_file: work + '/comments.jsonl', deferred_outcome: 'not_ready', deferred_status: 'todo', deferred_pull_request: 'null', deferred_failure_json: 'null',
        IIAUTO_DEFER_GITHUB_MUTATIONS: '1', IIAUTO_REPOSITORY_ID: task.repositoryId, IIAUTO_DISPATCH_ID: task.dispatchId,
        IIAUTO_PROJECT_ITEM_ID: task.projectItemId, IIAUTO_RESULT_FILE: work + '/result.json', IIAUTO_WORKSPACE_HELPER_FILE: '/__ii_os_materializer__',
        IIAUTO_GITHUB_APP_SLUG: task.appSlug, IIAUTO_AUTOMATION_ALLOWED_APP_SLUGS: task.appSlug,
      };
      for (const [key, field] of Object.entries({ IIAUTO_PROJECT_ID: 'projectId', IIAUTO_STATUS_FIELD_ID: 'statusFieldId',
        IIAUTO_STATUS_TODO_OPTION_ID: 'todoOptionId', IIAUTO_STATUS_IN_PROGRESS_OPTION_ID: 'inProgressOptionId',
        IIAUTO_STATUS_READY_FOR_QA_OPTION_ID: 'readyOptionId', IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID: 'humanOptionId' })) globals[key] = task[field] ?? '';
      if (task.submodule) {
        const extra = task.submodule, source = record.inputs.repositories.find(value => value.repository === extra.repository);
        if (!source || !/^[A-Za-z0-9_-][A-Za-z0-9._/-]{0,200}$/.test(extra.path ?? '') || extra.path.split('/').some(part => !part || part === '.' || part === '..' || part === '.git') ||
            !Number.isSafeInteger(extra.repositoryId) || extra.repositoryId < 1) throw Error('result-submodule-unapproved');
        Object.assign(globals, { submodule_path: worker.workspace + '/repository/' + extra.path, submodule_repository: extra.repository,
          submodule_repository_id: extra.repositoryId, submodule_base_sha: source.commit });
      }
      const delimiter = 'II_OS_MATERIALIZER_' + owner.replaceAll('-', '');
      if (sources.materializer.split('\n').includes(delimiter)) throw Error('result-helper-delimiter-conflict');
      const program = [
        'set -euo pipefail', ...Object.entries(globals).map(([key, value]) => `${key}=${quote(value)}`),
        // Provider values never enter this worker. Keep a bounded private
        // command diagnostic so a policy failure can be inspected after teardown.
        'exec 2> >(tail -c 8192 > ' + quote(work + '/policy.stderr') + ')',
        // Preserve the old exact-path guard, mapped from the helper's fixed
        // placeholder to the current Run's private result path. No arbitrary
        // output path is allowed.
        sources.core, sources.status.replace(resultPlaceholder, quote(work + '/result.json')),
        // Source is fixed, reviewed code on stdin. The worker cannot replace a
        // helper pathname between a digest check and Python opening the file.
        `python3() { test "$1" = /__ii_os_materializer__ || return 125; shift; /usr/bin/python3 - "$@" <<'${delimiter}'`,
        sources.materializer, delimiter, '}',
        'gh() { return 125; }', 'curl() { return 125; }',
        ': > "$deferred_comments_file"', 'chmod 0600 "$deferred_comments_file"',
        'write_deferred_outcome not_ready todo',
        'set +e', '(', 'set -euo pipefail', policy, ')', 'policy_status=$?', 'set -e',
        'printf \'{"policyExitCode":%s}\\n\' "$policy_status"', 'exec 2>&-', 'wait', '',
      ].join('\n');
      const bytes = Buffer.from(program);
      if (bytes.length > 2097152) throw Error('result-policy-input-limit');
      const policyOutput = await workerSession(worker, { command: '/usr/bin/env',
        args: ['-i', 'PATH=/usr/local/bin:/usr/bin:/bin', 'HOME=' + work, 'GIT_CONFIG_NOSYSTEM=1', 'GIT_CONFIG_GLOBAL=/dev/null', '/bin/bash', '-s'],
        ...context(), maxInputBytes: bytes.length, maxOutputBytes: 1048576 }, bytes);
      const policyReceipt = JSON.parse(policyOutput.toString('utf8').trim());
      if (!Number.isSafeInteger(policyReceipt.policyExitCode) || policyReceipt.policyExitCode < 0) throw Error('result-policy-unconfirmed');
      const resultBytes = await readWorkerFile(worker, work + '/result.json', 32768, context());
      const diagnosticBytes = await readWorkerFile(worker, work + '/policy.stderr', 8192, context());
      const result = JSON.parse(resultBytes.toString('utf8'));
      if (result.dispatch_id !== task.dispatchId || result.repository !== task.repository || result.repository_id !== task.repositoryId ||
          result.issue_number !== task.issueNumber || result.project_item_id !== task.projectItemId) throw Error('result-dispatch-mismatch');
      const destination = mkdtempSync(join(parent, 'collection-'));
      durable(join(destination, '.owner'), owner);
      durable(join(destination, 'result.json'), resultBytes);
      durable(join(destination, 'policy.stderr'), diagnosticBytes);
      const artifact = (name, value) => ({ reference: join(destination, name), digest: 'sha256:' + hash(value), bytes: value.length });
      let bundle = null;
      if (result.pull_request) {
        const value = await readWorkerFile(worker, work + '/change.bundle', 67108864, context());
        if (!value.length) throw Error('result-bundle-empty');
        durable(join(destination, 'change.bundle'), value); bundle = artifact('change.bundle', value);
      }
      const receipt = { schemaVersion: 1, executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest,
        result, resultArtifact: artifact('result.json', resultBytes), bundle, policyExitCode: policyReceipt.policyExitCode,
        diagnosticArtifact: artifact('policy.stderr', diagnosticBytes) };
      durable(join(destination, 'collection.json'), runtime.canonicalJson(receipt));
      for (const path of [destination, parent]) {
        const fd = openSync(path, 'r'); try { fsyncSync(fd); } finally { closeSync(fd); }
      }
      return receipt;
    },
  };
}
