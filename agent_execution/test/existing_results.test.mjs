import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createExistingResultCollector } from '../src/providers/github_actions/results.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const legacy = { core: '# generic core fixture', status: "# '/iif/job/artifacts/ii-os-agent-result.json'",
  execute: '# Codex launch code must not be selected\ncodex_failure_diagnostic() {\n  :\n}\n# generic policy fixture', materializer: '# generic materializer fixture' };
// The public kit helpers carry the neutral placeholder; both versions remain accepted.
const neutral = { ...legacy, status: "# '/ii-os-agent/artifacts/ii-os-agent-result.json'" };
const task = { repository: 'fixture/project', repositoryId: 1, issueNumber: 2, projectItemId: 'fixture-item', dispatchId: 'fixture-dispatch',
  appSlug: 'fixture-bot', promptDigest: 'c'.repeat(64) };
const result = { dispatch_id: task.dispatchId, repository: task.repository, repository_id: task.repositoryId, issue_number: task.issueNumber,
  project_item_id: task.projectItemId, outcome: 'not_ready', status: 'todo', comments: [], pull_request: null, automation_failure: null };

// Answers the collector's bounded worker transfers without a runtime; the
// policy program itself is captured, not executed.
function fakeWorker(calls) {
  const files = new Map();
  return { workspace: '/fixture/workspace', files,
    run: async request => { calls.push(['run', request.args[2]]); },
    open: async request => {
      let input = Buffer.alloc(0), ended;
      const done = new Promise(resolve => { ended = resolve; });
      const respond = () => {
        if (request.command === '/usr/bin/env') {
          calls.push(['policy', input.toString('utf8')]);
          files.set(request.args.find(value => value.startsWith('HOME=')).slice(5) + '/result.json', Buffer.from(JSON.stringify(result)));
          return Buffer.from('{"policyExitCode":0}\n');
        }
        const path = request.args[2];
        if (request.args[1].includes('O_EXCL')) { files.set(path, input); return Buffer.alloc(0); }
        return files.get(path) ?? Buffer.alloc(0);
      };
      return { output: (async function* () { await done; yield respond(); })(),
        write: async value => { input = Buffer.concat([input, value]); }, end: () => ended(),
        completion: done.then(() => ({ exitCode: 0 })), close: async () => {} };
    } };
}

function fixture(t, sources = legacy) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'existing-results-')), owner = randomUUID();
  writeFileSync(join(parent, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const helpers = {};
  for (const [name, source] of Object.entries(sources)) {
    const path = join(parent, 'helper-' + name); writeFileSync(path, source, { mode: 0o600 }); helpers[name] = { path, sha256: hash(source) };
  }
  const record = { executionId: 'fixture-run', attemptId: '1', inputDigest: 'sha256:' + 'd'.repeat(64), inputs: {
    environment: { II_OS_WORK_TICKET: JSON.stringify(task) }, configuration: { source: { repository: task.repository } },
    components: Object.entries(helpers).map(([name, helper]) => ({ name: 'result-helper-' + name, version: 'sha256:' + helper.sha256 })),
    repositories: [{ repository: task.repository, commit: 'b'.repeat(40) }] } };
  const telemetry = { executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest, captureComplete: true, transcript: '' };
  const collector = createExistingResultCollector({ runtime: { canonicalJson: JSON.stringify }, parent, task, helpers, readTelemetry: () => telemetry });
  return { parent, collector, record };
}
const collect = (collector, worker, record) => collector.collect({ worker, execution: { exitCode: 0 }, record,
  deadlineMs: Date.now() + 10000, signal: new AbortController().signal });

for (const [style, sources] of Object.entries({ legacy, neutral })) {
  test(`result collector maps the ${style} result placeholder to the run's private result path`, async t => {
    const { parent, collector, record } = fixture(t, sources), calls = [], worker = fakeWorker(calls);
    const receipt = await collect(collector, worker, record);
    assert.deepEqual(receipt.result, result);
    assert.equal(receipt.policyExitCode, 0);
    const program = calls.find(([kind]) => kind === 'policy')[1];
    const work = calls.find(([kind]) => kind === 'run')[1];
    assert.ok(work.startsWith('/fixture/workspace/ii-os-result-'));
    assert.ok(program.includes("# '" + work + "/result.json'"));
    assert.equal(program.includes('/artifacts/ii-os-agent-result.json'), false);
    assert.equal(program.includes('Codex launch code must not be selected'), false);
    assert.ok(program.includes('codex_failure_diagnostic() {'));
    assert.equal(readdirSync(parent).filter(name => name.startsWith('collection-')).length, 1);
  });
}

const ambiguous = {
  'legacy and neutral result placeholders': { status: legacy.status + '\n' + neutral.status },
  'two neutral result placeholders': { ...neutral, status: neutral.status + '\n' + neutral.status },
  'two legacy result placeholders': { status: legacy.status + '\n' + legacy.status },
  'no result placeholder': { status: '# generic status fixture' },
  'two policy markers': { ...neutral, execute: neutral.execute + '\ncodex_failure_diagnostic() {\n  :\n}' },
};
for (const [name, change] of Object.entries(ambiguous)) {
  test(`result collector refuses ${name} before any worker transfer`, async t => {
    const { collector, record } = fixture(t, { ...legacy, ...change }), calls = [];
    await assert.rejects(collect(collector, fakeWorker(calls), record), /^Error: result-policy-version-unsupported$/);
    assert.deepEqual(calls, []);
  });
}
