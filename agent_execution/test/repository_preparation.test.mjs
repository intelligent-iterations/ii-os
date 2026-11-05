import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { prepareApprovedRepositories } from '../src/providers/github_actions/preparation.mjs';
import { preparedTreeManifest } from '../src/providers/local/prepared_source.mjs';
import { inputs } from './fixtures/inputs.mjs';

test('Git preparation retains actual source bytes at the approved commit without persisting credentials or running hooks', async t => {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'git-preparation-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true }); });
  const runtime = await loadInstalledRuntime(), seed = join(root, 'seed'), parent = join(root, 'snapshots');
  mkdirSync(seed, { mode: 0o700 }); mkdirSync(parent, { mode: 0o700 });
  const executablePath = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin';
  const git = args => runtime.runTrustedProcess({ command: 'git', args, cwd: seed,
    env: { PATH: executablePath, HOME: root, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
      GIT_AUTHOR_NAME: 'Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.test', GIT_COMMITTER_NAME: 'Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.test' },
    timeoutMs: 10000, maxOutputBytes: 65536 });
  await git(['init', '--quiet']); writeFileSync(join(seed, 'approved.txt'), 'approved source bytes');
  await git(['add', 'approved.txt']); await git(['commit', '--quiet', '-m', 'Fixture source']);
  const commit = (await git(['rev-parse', 'HEAD'])).trim();
  const value = inputs(); value.repositories[0].commit = commit;
  const record = runtime.createExecutionInputRecord(value, { executionId: 'fixture-preparation', attemptId: '1' });
  const secret = 'synthetic-read-token-private';
  const transport = { ...runtime, runTrustedProcess: request => {
    assert.equal(request.args.some(arg => arg.includes(secret)), false);
    assert.equal(request.env.GIT_CONFIG_VALUE_1, '/dev/null');
    assert.equal(request.env.GIT_CONFIG_VALUE_2, '');
    // Only the transport is substituted: real Git still verifies objects,
    // checks out the immutable revision and writes its actual metadata.
    const args = request.args[0] === 'fetch' ? ['-c', 'protocol.file.allow=always', '-c', `url.file://${seed}/.insteadOf=https://github.com/fixture/project.git`, ...request.args] : request.args;
    return runtime.runTrustedProcess({ ...request, args });
  } };
  const result = await prepareApprovedRepositories({ runtime: transport, parent, compiled: runtime.compileConfiguration(value.configuration), record,
    credential: { read: async () => Buffer.from(secret) }, branch: 'ii-os-agent/' + 'a'.repeat(32), executablePath,
    repositories: [{ repository: 'fixture/project', commit, path: '' }] });
  assert.equal(readFileSync(join(result.preparedDirectory, 'approved.txt'), 'utf8'), 'approved source bytes');
  assert.deepEqual(result.manifest, preparedTreeManifest(result.preparedDirectory));
  const config = readFileSync(join(result.preparedDirectory, '.git/config'), 'utf8');
  assert.equal(config.includes(secret), false); assert.equal(config.includes('extraheader'), false);
  assert.ok(config.includes('https://github.com/fixture/project.git'));
  // The existing collector fetches this exact object database into a fresh
  // trusted repository. Shallow input silently rejects FETCH_HEAD here.
  const trusted = join(root, 'trusted'); mkdirSync(trusted, { mode: 0o700 });
  await git(['-C', trusted, 'init', '--quiet']);
  await git(['-C', trusted, 'fetch', '--no-tags', join(result.preparedDirectory, '.git'), commit]);
  await git(['-C', trusted, 'checkout', '--quiet', '-b', 'fixture', 'FETCH_HEAD']);
  assert.equal((await git(['-C', trusted, 'rev-parse', 'HEAD'])).trim(), commit);
  const previous = readdirSync(parent);
  await assert.rejects(prepareApprovedRepositories({ runtime: transport, parent, compiled: runtime.compileConfiguration(value.configuration), record,
    credential: { read: async () => { assert.fail('denied source must not acquire credentials'); } }, branch: 'ii-os-agent/' + 'a'.repeat(32), executablePath,
    repositories: [{ repository: 'fixture/other', commit, path: '' }] }), /source-denied/);
  assert.deepEqual(readdirSync(parent), previous);
});
