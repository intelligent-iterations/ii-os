import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';
import { preparedTreeManifest } from '../local/prepared_source.mjs';

const repositoryName = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

/** Trusted Git preparation; credentials stay in Git's environment, outside the worker. */
export async function prepareApprovedRepositories({ runtime, parent, compiled, record, credential, branch, repositories, executablePath, signal }) {
  const info = lstatSync(parent);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || (info.mode & 0o077) || realpathSync(parent) !== parent ||
      !/^ii-os-agent\/[a-f0-9]{32}$/.test(branch ?? '') || !Array.isArray(repositories) || !repositories.length || repositories.length > 11 ||
      !/^\/[A-Za-z0-9/_-]+(?::\/[A-Za-z0-9/_-]+)*$/.test(executablePath ?? '')) throw Error('repository-preparation-binding-invalid');
  const configuration = runtime.compileConfiguration(record.inputs.configuration);
  if (configuration.canonical !== compiled.canonical) throw Error('repository-preparation-configuration-mismatch');
  const allowed = new Set([configuration.configuration.source.repository,
    ...configuration.configuration.source.additionalRepositories.map(value => value.repository)]);
  const seen = new Set(), destinations = new Set();
  for (const [index, source] of repositories.entries()) {
    if (!repositoryName.test(source.repository ?? '') || !allowed.has(source.repository) || seen.has(source.repository) ||
        !/^[a-f0-9]{40}$/.test(source.commit ?? '') ||
        !record.inputs.repositories.some(value => value.repository === source.repository && value.commit === source.commit && value.localChanges === null) ||
        (index === 0 ? source.path !== '' || source.repository !== configuration.configuration.source.repository :
          !/^[A-Za-z0-9_-][A-Za-z0-9._/-]{0,200}$/.test(source.path ?? '') || source.path.split('/').some(part => !part || part === '.' || part === '..' || part === '.git')) ||
        destinations.has(source.path)) throw Error('repository-preparation-source-denied');
    seen.add(source.repository); destinations.add(source.path);
  }
  if (repositories.length !== record.inputs.repositories.length) throw Error('repository-preparation-source-denied');
  const token = (await credential.read()).toString('utf8');
  if (!/^[\x21-\x7e]{20,8192}$/.test(token)) throw Error('repository-preparation-credential-invalid');
  const root = mkdtempSync(join(parent, 'source-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner, { mode: 0o600, flag: 'wx' });
  const directory = join(root, 'repository');
  const deadlineMs = Date.now() + 300000;
  const env = { PATH: executablePath, HOME: root, GIT_TERMINAL_PROMPT: '0', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_COUNT: '4', GIT_CONFIG_KEY_0: 'http.https://github.com/.extraheader',
    GIT_CONFIG_VALUE_0: `AUTHORIZATION: basic ${Buffer.from('x-access-token:' + token).toString('base64')}`,
    GIT_CONFIG_KEY_1: 'core.hooksPath', GIT_CONFIG_VALUE_1: '/dev/null',
    GIT_CONFIG_KEY_2: 'credential.helper', GIT_CONFIG_VALUE_2: '',
    GIT_CONFIG_KEY_3: 'http.followRedirects', GIT_CONFIG_VALUE_3: 'false' };
  const git = (cwd, args) => runtime.runTrustedProcess({ command: 'git', args, cwd, env,
    timeoutMs: Math.min(120000, deadlineMs - Date.now()), maxOutputBytes: 1048576, ...(signal ? { signal } : {}) });
  try {
    for (const [index, source] of repositories.entries()) {
      const target = index === 0 ? directory : join(directory, source.path);
      if (index > 0) {
        const entry = (await git(directory, ['ls-files', '--stage', '--', source.path])).trim();
        if (!/^160000 [a-f0-9]{40} 0\t/.test(entry) || entry.split('\t')[1] !== source.path) throw Error('repository-preparation-submodule-denied');
        // The destination must still be Git's empty gitlink directory. Never
        // recurse through a repository-controlled symlink or replace its data.
        const parentPath = dirname(target);
        if (realpathSync(parentPath) !== parentPath || parentPath !== directory && !parentPath.startsWith(directory + '/')) throw Error('repository-preparation-submodule-denied');
      }
      try { mkdirSync(target, { mode: 0o700 }); }
      catch (error) {
        if (error.code !== 'EEXIST' || index === 0 || !lstatSync(target).isDirectory() || lstatSync(target).isSymbolicLink() || readdirSync(target).length) throw Error('repository-preparation-destination-not-empty');
      }
      await git(target, ['init', '--quiet']);
      await git(target, ['remote', 'add', 'origin', `https://github.com/${source.repository}.git`]);
      // Preserve the existing worker's complete object database. Its reviewed
      // materializer imports this base into a fresh trusted Git repository;
      // shallow roots reject that FETCH_HEAD and prevent bundle collection.
      await git(target, ['fetch', '--no-tags', 'origin', source.commit]);
      await git(target, ['checkout', '--quiet', '-b', branch, source.commit]);
      if ((await git(target, ['rev-parse', 'HEAD'])).trim() !== source.commit) throw Error('repository-preparation-revision-mismatch');
    }
    const manifest = preparedTreeManifest(directory);
    writeFileSync(join(root, 'manifest.json'), manifest.canonical, { mode: 0o600, flag: 'wx' });
    writeFileSync(join(root, 'sources.json'), runtime.canonicalJson({ branch, repositories }), { mode: 0o600, flag: 'wx' });
    return { preparedDirectory: directory, manifest,
      artifact: { reference: directory, digest: manifest.digest, bytes: manifest.bytes } };
  } catch {
    if (realpathSync(root) !== root || readFileSync(join(root, '.owner'), 'utf8') !== owner) throw Error('repository-preparation-cleanup-unconfirmed');
    rmSync(root, { recursive: true });
    throw Error('repository-preparation-failed');
  }
}
