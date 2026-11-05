// Resolve ii-os's agent_execution package and the controller's private paths.
// The host provider sets every value; the controller never guesses a location.
import { lstatSync, mkdirSync, realpathSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { pathToFileURL } from 'node:url';

function canonical(name) {
  const value = process.env[name];
  if (typeof value !== 'string' || !isAbsolute(value) || realpathSync(value) !== value) throw Error('controller-path-invalid:' + name);
  return value;
}

/** A directory only this user can reach, optionally created first. */
export function privateDirectory(path, create = false) {
  if (create) {
    try { mkdirSync(path, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || info.mode & 0o077 || realpathSync(path) !== path) throw Error('controller-private-directory-invalid');
  return path;
}

/** Persistent execution state, the admission ledger and the job-scoped scratch area. */
export function controllerPaths() {
  return {
    state: privateDirectory(canonical('II_OS_CONTROLLER_STATE_DIR')),
    admission: privateDirectory(canonical('II_OS_CONTROLLER_ADMISSION_DIR')),
    scratch: privateDirectory(canonical('II_OS_CONTROLLER_SCRATCH_DIR')),
  };
}

/** Import one module of the agent_execution package installed on this host. */
export async function importExecution(relative) {
  if (!/^src\/[a-z_/]+\.mjs$/.test(relative)) throw Error('agent-execution-module-invalid');
  return import(pathToFileURL(join(canonical('II_OS_AGENT_EXECUTION_DIR'), relative)).href);
}

/** Validate the ii-os API base the workflow configured. */
export function connectorUrl(value) {
  let url;
  try { url = new URL(value); } catch { throw Error('connector-url-invalid'); }
  const local = url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname);
  if (url.protocol !== 'https:' && !local || url.username || url.password || url.search || url.hash || value.endsWith('/')) throw Error('connector-url-invalid');
  return value;
}
