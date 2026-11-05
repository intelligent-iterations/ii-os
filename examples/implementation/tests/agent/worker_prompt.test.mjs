// The kit's prepare/core/status helpers are accepted by agent_execution's
// prompt bridge and render the approved ticket into the run's prompt.
//
// Set II_OS_AGENT_EXECUTION_DIR to an installed agent_execution package
// (npm ci done); the default is the repository's own copy.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash, randomUUID } from 'node:crypto';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const workerDirectory = resolve(here, '../../scripts/agent/worker');
const agentExecution = resolve(process.env.II_OS_AGENT_EXECUTION_DIR || join(here, '../../../../agent_execution'));
const { prepareExistingTicketPrompt } = await import(pathToFileURL(join(agentExecution, 'src/providers/github_actions/prompt.mjs')).href);
const { loadInstalledRuntime } = await import(pathToFileURL(join(agentExecution, 'src/providers/agent_runtime/installed.mjs')).href);

const sha256 = value => createHash('sha256').update(value).digest('hex');
const helperFiles = { core: 'agent-work-ticket-core.sh', status: 'agent-work-ticket-status.sh', prepare: 'agent-work-ticket-prepare.sh' };

// The prompt program runs with exactly this PATH: jq plus the base system.
function executablePath() {
  const jq = (process.env.PATH ?? '').split(':').find(directory => directory.startsWith('/') && existsSync(join(directory, 'jq')));
  assert.ok(jq, 'jq is required on PATH');
  return [...new Set([jq, '/usr/local/bin', '/usr/bin', '/bin'])].filter(directory => /^\/[A-Za-z0-9/_-]+$/.test(directory)).join(':');
}

function fixture(t, ticket = {}) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'worker-prompt-')), owner = randomUUID();
  writeFileSync(join(parent, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  // Stage private, owner-only copies, as the credential handoff does.
  const helpers = {};
  for (const [name, file] of Object.entries(helperFiles)) {
    const path = join(parent, file); copyFileSync(join(workerDirectory, file), path);
    helpers[name] = { path, sha256: sha256(readFileSync(path)) };
  }
  const task = { repository: 'acme-co/example-app', repositoryId: 4242, issueNumber: 17, projectItemId: 'PVTI_example17',
    dispatchId: 'human:PVTI_example17', appSlug: 'example-app-bot' };
  const approved = { schema_version: 1, project_id: 'PVT_example', project_item_id: task.projectItemId, repository_id: task.repositoryId,
    repository: task.repository, issue_number: task.issueNumber, title: 'Add a dark-mode toggle',
    body: 'Add a toggle to the settings page.\n\nAcceptance: the choice survives a reload.', activation_response: 'Use the existing theme tokens.', ...ticket };
  const approvedBytes = Buffer.from(JSON.stringify(approved));
  const profile = { id: 'example-agent', version: '3', engine: 'codex',
    allowed_actions: ['Edit files in the repository.'], denied_actions: ['Do not deploy to production.'] };
  return { parent, helpers, task, approvedBytes, approvedDigest: sha256(approvedBytes), executablePath: executablePath(), profile };
}

test('agent_execution renders the approved ticket through the kit helpers', async t => {
  const options = fixture(t), runtime = await loadInstalledRuntime();
  const prompt = await prepareExistingTicketPrompt({ ...options, runtime });
  const text = prompt.text;
  assert.equal(prompt.sha256, sha256(Buffer.from(text)));
  assert.equal(prompt.approvedDigest, options.approvedDigest);
  assert.deepEqual(prompt.components.map(component => component.name), ['prompt-helper-core', 'prompt-helper-status', 'prompt-helper-prepare']);
  assert.deepEqual(prompt.components.map(component => component.version),
    ['core', 'status', 'prepare'].map(name => 'sha256:' + options.helpers[name].sha256));
  assert.equal(text.split('You are running inside an agent-runtime ephemeral container.').length, 2);
  for (const expected of ['Issue: https://github.com/acme-co/example-app/issues/17', 'Stream ID: github:acme-co/example-app#17',
    'Repository: acme-co/example-app', 'Base branch: dev', 'Permission profile: example-agent@3', '- Edit files in the repository.',
    '- Do not deploy to production.', 'Title: Add a dark-mode toggle', 'Acceptance: the choice survives a reload.',
    'Use the existing theme tokens.', '## Status Decision']) assert.ok(text.includes(expected), expected);
  assert.equal(readdirSync(options.parent).some(name => name.startsWith('prompt-')), false);
});

for (const [name, ticket] of Object.entries({
  'another issue': { issue_number: 18 },
  'another repository identity': { repository_id: 4243 },
  'an unreviewed field': { assignee: 'alice' },
})) {
  test(`the kit prepare helper refuses an approved ticket for ${name}`, async t => {
    const options = fixture(t, ticket), runtime = await loadInstalledRuntime();
    await assert.rejects(prepareExistingTicketPrompt({ ...options, runtime }), /^Error: existing-prompt-preparation-failed$/);
    assert.equal(readdirSync(options.parent).some(name => name.startsWith('prompt-')), false);
  });
}

test('a changed kit helper is refused before any process runs', async t => {
  const options = fixture(t);
  writeFileSync(options.helpers.prepare.path, readFileSync(options.helpers.prepare.path, 'utf8') + '\n# unreviewed change\n');
  let calls = 0;
  const runtime = { canonicalJson: JSON.stringify, runTrustedProcess: async () => { calls++; } };
  await assert.rejects(prepareExistingTicketPrompt({ ...options, runtime }), /^Error: prompt-helper-integrity$/);
  assert.equal(calls, 0);
});
