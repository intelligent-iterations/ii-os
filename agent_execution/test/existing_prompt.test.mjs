import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { prepareExistingTicketPrompt } from '../src/providers/github_actions/prompt.mjs';

const legacy = { core: '# generic core fixture', status: "# '/iif/job/artifacts/ii-os-agent-result.json'",
  prepare: '# You are running inside a Fleet-managed ephemeral container.\n# generic preparation fixture\nprompt_sha="$(file_sha256 "$prompt_file")"\n# Git/model code must not be selected' };
// The public kit helpers carry neutral markers; both versions remain accepted.
const neutral = { core: '# generic core fixture', status: "# '/ii-os-agent/artifacts/ii-os-agent-result.json'",
  prepare: '# You are running inside an agent-runtime ephemeral container.\n# generic preparation fixture\nprompt_sha="$(file_sha256 "$prompt_file")"\n# Git/model code must not be selected' };
const quote = value => "'" + String(value).replaceAll("'", "'\"'\"'") + "'";

function fixture(t, sources = legacy) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'existing-prompt-')), owner = randomUUID();
  writeFileSync(join(parent, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const helpers = {};
  for (const [name, source] of Object.entries(sources)) {
    const path = join(parent, name); writeFileSync(path, source, { mode: 0o600 }); helpers[name] = { path, sha256: hash(source) };
  }
  const approvedBytes = Buffer.from('{"fixture":"approved snapshot"}');
  const options = { parent, helpers, approvedBytes, approvedDigest: hash(approvedBytes), executablePath: '/usr/local/bin:/usr/bin:/bin',
    profile: { id: 'fixture-agent', version: 'fixture-version', engine: 'codex', allowed_actions: ['Complete the approved task.'], denied_actions: [] },
    task: { repository: 'fixture/project', repositoryId: 1, issueNumber: 2, projectItemId: 'fixture-item', dispatchId: 'fixture-dispatch', appSlug: 'fixture-bot' },
    runtime: { canonicalJson: JSON.stringify, runTrustedProcess: async request => {
      const program = readFileSync(request.args[0], 'utf8');
      assert.ok(program.includes('You are running inside an agent-runtime ephemeral container.'));
      assert.equal(program.includes('Fleet-managed'), false);
      assert.ok(program.includes('# ' + quote(join(request.cwd, 'result.json'))));
      assert.equal(program.includes('/artifacts/ii-os-agent-result.json'), false);
      assert.equal(program.includes('Git/model code must not be selected'), false);
      assert.equal(readFileSync(request.env.IIAUTO_TICKET_PROMPT_FILE, 'utf8'), approvedBytes.toString());
      assert.equal(request.env.GH_TOKEN, undefined); assert.equal(request.env.CODEX_AUTH_JSON, undefined);
      assert.equal(request.timeoutMs, 15000);
      writeFileSync(join(request.cwd, 'prompt.md'), 'Rendered generic fixture prompt.'); return '';
    } } };
  return options;
}

test('prompt bridge uses the approved source prefix without Git, model or ambient credentials', async t => {
  const options = fixture(t);
  const result = await prepareExistingTicketPrompt(options);
  assert.equal(result.text, 'Rendered generic fixture prompt.');
  assert.equal(result.approvedDigest, options.approvedDigest);
  assert.equal(result.components.length, 3);
  assert.equal(readdirSync(options.parent).some(name => name.startsWith('prompt-')), false);
});

test('changed approval or helper bytes fail before process execution', async t => {
  const options = fixture(t); let calls = 0;
  options.runtime.runTrustedProcess = async () => { calls++; };
  await assert.rejects(prepareExistingTicketPrompt({ ...options, approvedDigest: 'a'.repeat(64) }), /binding-invalid/);
  writeFileSync(options.helpers.prepare.path, 'unapproved policy');
  await assert.rejects(prepareExistingTicketPrompt(options), /helper-integrity/);
  assert.equal(calls, 0);
});

test('process failure is redacted and removes only the marked prompt scratch directory', async t => {
  const options = fixture(t);
  options.runtime.runTrustedProcess = async () => { throw Error('synthetic-private-provider-error'); };
  await assert.rejects(prepareExistingTicketPrompt(options), error => error.message === 'existing-prompt-preparation-failed');
  assert.equal(readdirSync(options.parent).some(name => name.startsWith('prompt-')), false);
  assert.ok(readFileSync(options.helpers.core.path).length);
});

test('prompt bridge accepts the neutral kit markers and maps the result placeholder to the private path', async t => {
  const options = fixture(t, neutral);
  const result = await prepareExistingTicketPrompt(options);
  assert.equal(result.text, 'Rendered generic fixture prompt.');
  assert.equal(result.components.length, 3);
  assert.equal(readdirSync(options.parent).some(name => name.startsWith('prompt-')), false);
});

const ambiguous = {
  'legacy and neutral boundary sentences': { prepare: legacy.prepare.replace('# generic', '# You are running inside an agent-runtime ephemeral container.\n# generic') },
  'two neutral boundary sentences': { ...neutral, prepare: neutral.prepare.replace('# generic', '# You are running inside an agent-runtime ephemeral container.\n# generic') },
  'no boundary sentence': { prepare: '# generic preparation fixture\nprompt_sha="$(file_sha256 "$prompt_file")"' },
  'legacy and neutral result placeholders': { status: legacy.status + '\n' + neutral.status },
  'two neutral result placeholders': { ...neutral, status: neutral.status + '\n' + neutral.status },
  'no result placeholder': { status: '# generic status fixture' },
  'two preparation markers': { ...neutral, prepare: neutral.prepare + '\nprompt_sha="$(file_sha256 "$prompt_file")"' },
};
for (const [name, change] of Object.entries(ambiguous)) {
  test(`prompt bridge refuses ${name} before process execution`, async t => {
    const options = fixture(t, { ...legacy, ...change }); let calls = 0;
    options.runtime.runTrustedProcess = async () => { calls++; };
    await assert.rejects(prepareExistingTicketPrompt(options), /^Error: prompt-policy-version-unsupported$/);
    assert.equal(calls, 0);
  });
}
