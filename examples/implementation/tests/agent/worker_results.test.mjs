// agent_execution's result collector accepts the kit's execute, status and
// core helpers and the workspace materializer, and turns a finished workspace
// into the bounded result and Git bundle that ii-os publishes.
//
// The worker double runs the collector's fixed commands (/usr/bin/python3,
// /usr/bin/env -i ... /bin/bash -s) on this machine inside a throwaway
// workspace; no container, network or credential is involved.
// Set II_OS_AGENT_EXECUTION_DIR to an installed agent_execution package.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn, execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const workerDirectory = resolve(here, '../../scripts/agent/worker');
const agentExecution = resolve(process.env.II_OS_AGENT_EXECUTION_DIR || join(here, '../../../../agent_execution'));
const { createExistingResultCollector } = await import(pathToFileURL(join(agentExecution, 'src/providers/github_actions/results.mjs')).href);
const { loadInstalledRuntime } = await import(pathToFileURL(join(agentExecution, 'src/providers/agent_runtime/installed.mjs')).href);

const sha256 = value => createHash('sha256').update(value).digest('hex');
const helperFiles = { core: 'agent-work-ticket-core.sh', status: 'agent-work-ticket-status.sh',
  execute: 'agent-work-ticket-execute.sh', materializer: 'agent_workspace_materialize.py' };
// The collector's program runs with this fixed PATH inside the worker.
const workerPath = ['/usr/local/bin', '/usr/bin', '/bin'];
const missing = ['/usr/bin/python3', '/usr/bin/env', '/bin/bash'].filter(path => !existsSync(path))
  .concat(['jq', 'git'].filter(name => !workerPath.some(directory => existsSync(join(directory, name)))));
const skip = missing.length ? `worker toolchain unavailable here: ${missing.join(', ')}` : false;

const git = (cwd, ...args) => execFileSync('git', ['-c', 'user.name=Example Maintainer', '-c', 'user.email=alice@example.com',
  '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false', ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  env: { PATH: process.env.PATH, HOME: cwd, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null' } }).trim();
function repository(path, files) {
  mkdirSync(path, { recursive: true });
  git(path, 'init', '-q'); git(path, 'checkout', '-q', '-b', 'dev');
  for (const [name, text] of Object.entries(files)) { mkdirSync(dirname(join(path, name)), { recursive: true }); writeFileSync(join(path, name), text); }
  git(path, 'add', '-A'); git(path, 'commit', '-q', '-m', 'base');
  return git(path, 'rev-parse', 'HEAD');
}

// Executes each requested command locally; the transfer protocol is the
// runtime's (stdin in, stdout out, exit status).
function localWorker(workspace) {
  const start = request => spawn(request.command, request.args, { cwd: workspace, stdio: ['pipe', 'pipe', 'pipe'] });
  return { workspace,
    run: async request => {
      const child = start(request); child.stdin.end(); child.stdout.resume(); child.stderr.resume();
      const code = await new Promise(done => child.on('close', done));
      if (code !== 0) throw Error('worker-run-failed');
    },
    open: async request => {
      const child = start(request); child.stderr.resume();
      return { output: child.stdout, end: () => child.stdin.end(),
        write: value => new Promise((done, fail) => child.stdin.write(value, error => error ? fail(error) : done())),
        completion: new Promise(done => child.on('close', exitCode => done({ exitCode }))),
        close: async () => { if (child.exitCode === null && child.signalCode === null) child.kill(); } };
    } };
}

function fixture(t, { submodule = false } = {}) {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'worker-results-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true, force: true }); });
  const parent = join(root, 'collections'), workspace = join(root, 'workspace');
  mkdirSync(parent, { mode: 0o700 }); mkdirSync(workspace, { mode: 0o700 });
  const helpers = {};
  for (const [name, file] of Object.entries(helperFiles)) {
    const path = join(root, file); copyFileSync(join(workerDirectory, file), path);
    helpers[name] = { path, sha256: sha256(readFileSync(path)) };
  }
  const main = join(workspace, 'repository');
  const repositories = [{ repository: 'acme-co/example-app', commit: repository(main, { 'README.md': '# Example app\n', 'lib/settings.txt': 'theme=light\n' }) }];
  const task = { repository: 'acme-co/example-app', repositoryId: 4242, issueNumber: 17, projectItemId: 'PVTI_example17',
    dispatchId: 'human:PVTI_example17', appSlug: 'example-app-bot', promptDigest: 'c'.repeat(64),
    gitName: 'example-app-bot[bot]', gitEmail: 'example-app-bot[bot]@users.noreply.github.com',
    projectId: 'PVT_example', statusFieldId: 'PVTSSF_status', todoOptionId: 'opt-todo', inProgressOptionId: 'opt-progress',
    readyOptionId: 'opt-ready', humanOptionId: 'opt-human' };
  if (submodule) {
    // agent_execution prepares an approved submodule as its own checkout at
    // the parent's gitlink path; the policy publishes whichever one changed.
    const path = 'vendor/example-lib', commit = repository(join(main, path), { 'lib.txt': 'version=1\n' });
    git(main, 'update-index', '--add', '--cacheinfo', `160000,${commit},${path}`); git(main, 'commit', '-q', '-m', 'add library');
    repositories[0].commit = git(main, 'rev-parse', 'HEAD');
    repositories.push({ repository: 'acme-co/example-lib', commit });
    task.submodule = { repository: 'acme-co/example-lib', path, repositoryId: 4343 };
  }
  return { root, parent, workspace, main, helpers, task, repositories };
}

async function collect({ parent, workspace, helpers, task, repositories }, { exitCode = 0, transcript = '' } = {}) {
  const runtime = await loadInstalledRuntime();
  const record = { executionId: 'github:4242:100:work-ticket', attemptId: '1', inputDigest: 'sha256:' + 'd'.repeat(64), inputs: {
    environment: { II_OS_WORK_TICKET: runtime.canonicalJson(task) }, configuration: { source: { repository: task.repository } },
    components: Object.entries(helpers).map(([name, helper]) => ({ name: 'result-helper-' + name, version: 'sha256:' + helper.sha256 })),
    repositories } };
  const telemetry = { executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest, captureComplete: true, transcript };
  const collector = createExistingResultCollector({ runtime, parent, task, helpers, readTelemetry: () => telemetry });
  return collector.collect({ worker: localWorker(workspace), execution: { exitCode }, record,
    deadlineMs: Date.now() + 60000, signal: new AbortController().signal });
}

const readyNote = `# Result

Added a persisted dark-mode toggle.

## Status Decision

- Human input needed: No.
- Question for human: None.
- What is needed: None.
- How to answer: None.
- How human can provide it: None.
- Ready for QA: Yes.
- QA artifact: https://dev.example-app.example.com/settings (deployed to dev)
- QA method: Open the settings page, switch dark mode on, reload the page and confirm the dark theme is still applied.
- Verification: Ran the settings tests; all passed.
- Assumptions/proposal: None.
`;
const committed = (repositoryPath, bundle, branch) => {
  git(repositoryPath, 'bundle', 'verify', bundle);
  git(repositoryPath, 'fetch', '-q', bundle, `refs/heads/${branch}:refs/remotes/bundle/result`);
  return { files: git(repositoryPath, 'show', '--name-only', '--format=', 'refs/remotes/bundle/result').split('\n').sort(),
    author: git(repositoryPath, 'show', '-s', '--format=%an <%ae>', 'refs/remotes/bundle/result'),
    head: git(repositoryPath, 'rev-parse', 'refs/remotes/bundle/result') };
};

test('a ready change becomes a deferred pull request intent and a verified bundle', { skip }, async t => {
  const context = fixture(t), { main, task, repositories } = context;
  writeFileSync(join(main, 'lib/settings.txt'), 'theme=light\ntoggle=dark-mode\n');
  mkdirSync(join(main, 'docs')); writeFileSync(join(main, 'docs/dark-mode.md'), 'Settings has a dark-mode toggle.\n');
  writeFileSync(join(main, '.auto-agent-result.md'), readyNote);
  const receipt = await collect(context);
  const branch = 'ii-os-agent/' + sha256(task.dispatchId).slice(0, 32);
  assert.equal(receipt.policyExitCode, 0, readFileSync(receipt.diagnosticArtifact.reference, 'utf8'));
  const { result } = receipt;
  assert.deepEqual(Object.keys(result).sort(), ['automation_failure', 'comments', 'dispatch_id', 'issue_number', 'outcome',
    'project_item_id', 'pull_request', 'repository', 'repository_id', 'status']);
  assert.equal(result.outcome, 'ready_for_qa'); assert.equal(result.status, 'ready_for_qa'); assert.equal(result.automation_failure, null);
  assert.equal(result.comments.length, 1);
  assert.match(result.comments[0], /Status decision: Ready for QA/);
  assert.match(result.comments[0], /Runtime cleanup is still being verified/);
  const bundled = committed(main, receipt.bundle.reference, branch);
  assert.deepEqual(result.pull_request, { repository: 'acme-co/example-app', repository_id: 4242, head: branch, base: 'dev',
    head_sha: bundled.head, base_sha: repositories[0].commit, expected_old_head_sha: null });
  assert.deepEqual(bundled.files, ['docs/dark-mode.md', 'lib/settings.txt']);
  assert.equal(bundled.author, 'example-app-bot[bot] <example-app-bot[bot]@users.noreply.github.com>');
  assert.equal(receipt.bundle.digest, 'sha256:' + sha256(readFileSync(receipt.bundle.reference)));
});

test('a change inside the approved submodule is published for that repository', { skip }, async t => {
  const context = fixture(t, { submodule: true }), { main, task, repositories } = context;
  writeFileSync(join(main, 'vendor/example-lib/lib.txt'), 'version=2\n');
  writeFileSync(join(main, '.auto-agent-result.md'), readyNote);
  const receipt = await collect(context);
  assert.equal(receipt.policyExitCode, 0, readFileSync(receipt.diagnosticArtifact.reference, 'utf8'));
  const branch = 'ii-os-agent/' + sha256(task.dispatchId).slice(0, 32);
  const bundled = committed(join(main, 'vendor/example-lib'), receipt.bundle.reference, branch);
  assert.deepEqual(receipt.result.pull_request, { repository: 'acme-co/example-lib', repository_id: 4343, head: branch, base: 'dev',
    head_sha: bundled.head, base_sha: repositories[1].commit, expected_old_head_sha: null });
  assert.deepEqual(bundled.files, ['lib.txt']);
  assert.equal(receipt.result.outcome, 'ready_for_qa');
});

test('an expired Codex login is recorded as a deferred automation failure', { skip }, async t => {
  const context = fixture(t);
  const receipt = await collect(context, { exitCode: 1,
    transcript: '{"type":"error","message":"refresh_token_reused: please sign in again"}\n' });
  assert.equal(receipt.policyExitCode, 1);
  assert.equal(receipt.bundle, null);
  const { result } = receipt;
  assert.equal(result.outcome, 'not_ready'); assert.equal(result.status, 'todo'); assert.equal(result.pull_request, null);
  assert.deepEqual(result.automation_failure, { code: 'codex_oauth_refresh_failed', detail: 'The Codex OAuth session could not be refreshed.' });
  assert.ok(result.comments[0].startsWith('<!-- ii-os:codex-auth-failed -->\n'));
  assert.match(result.comments[1], /Actor: example-app-bot\[bot\] \(Bot\)/);
  assert.match(result.comments[1], /Status: In Progress -> Todo/);
});

test('a link escaping the workspace is refused and nothing is published', { skip }, async t => {
  const context = fixture(t), { main } = context;
  writeFileSync(join(main, 'README.md'), '# Example app\n\nChanged.\n');
  symlinkSync('/etc/passwd', join(main, 'escape'));
  writeFileSync(join(main, '.auto-agent-result.md'), readyNote);
  const receipt = await collect(context);
  assert.notEqual(receipt.policyExitCode, 0);
  assert.equal(receipt.bundle, null);
  assert.equal(receipt.result.pull_request, null); assert.equal(receipt.result.outcome, 'not_ready');
  assert.match(readFileSync(receipt.diagnosticArtifact.reference, 'utf8'), /guest workspace contains a link or special file/);
});
