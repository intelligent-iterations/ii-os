import { closeSync, constants, fstatSync, lstatSync, mkdtempSync, openSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { join } from 'node:path';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const quote = value => "'" + String(value).replaceAll("'", "'\"'\"'") + "'";
/** The one marker of `markers` that occurs exactly once while no other occurs, or null. */
export const exactlyOne = (source, markers) => {
  const found = markers.filter(value => source.includes(value));
  return found.length === 1 && source.split(found[0]).length === 2 ? found[0] : null;
};
function helperSource(helper) {
  const fd = openSync(helper.path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 || stat.mode & 0o022 || stat.size > 524288) throw Error('prompt-helper-integrity');
    const bytes = readFileSync(fd);
    if (bytes.length !== stat.size || digest(bytes) !== helper.sha256) throw Error('prompt-helper-integrity');
    return bytes.toString('utf8');
  } finally { closeSync(fd); }
}

/** Render the existing approved prompt policy before any Git or model execution. */
export async function prepareExistingTicketPrompt({ runtime, parent, helpers, profile, task, approvedBytes, approvedDigest, executablePath, signal }) {
  const stat = lstatSync(parent);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || stat.mode & 0o077 || realpathSync(parent) !== parent ||
      !Buffer.isBuffer(approvedBytes) || !approvedBytes.length || approvedBytes.length > 65536 || digest(approvedBytes) !== approvedDigest ||
      !/^\/[A-Za-z0-9/_-]+(?::\/[A-Za-z0-9/_-]+)*$/.test(executablePath ?? '') || profile?.engine !== 'codex' ||
      !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(task?.repository ?? '') ||
      !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(task.dispatchId ?? '') ||
      !/^[A-Za-z0-9][A-Za-z0-9-]{0,99}$/.test(task.appSlug ?? '') ||
      !['repositoryId', 'issueNumber'].every(key => Number.isSafeInteger(task[key]) && task[key] > 0) ||
      !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(task.projectItemId ?? '') ||
      !['allowed_actions', 'denied_actions'].every(key => Array.isArray(profile[key]) && profile[key].length <= 64 && profile[key].every(value => typeof value === 'string' && value.length <= 300))) throw Error('prompt-preparation-binding-invalid');
  const sources = Object.fromEntries(['core', 'status', 'prepare'].map(name => [name, helperSource(helpers[name])]));
  const marker = '\nprompt_sha="$(file_sha256 "$prompt_file")"';
  const boundary = 'You are running inside an agent-runtime ephemeral container.';
  // Existing helpers carry the old backend's sentence and result path; the
  // public kit helpers carry neutral ones. Exactly one marker of one version.
  const oldBoundary = 'You are running inside a Fleet-managed ephemeral container.';
  const resultPlaceholder = exactlyOne(sources.status, ["'/iif/job/artifacts/ii-os-agent-result.json'", "'/ii-os-agent/artifacts/ii-os-agent-result.json'"]);
  if (sources.prepare.split(marker).length !== 2 || !exactlyOne(sources.prepare, [oldBoundary, boundary]) || !resultPlaceholder) throw Error('prompt-policy-version-unsupported');
  // The same prompt text and approval checks remain authoritative. Only the
  // old execution backend sentence changes to describe the actual boundary.
  const policy = sources.prepare.slice(0, sources.prepare.indexOf(marker)).replace(oldBoundary, boundary);
  const root = mkdtempSync(join(parent, 'prompt-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner, { mode: 0o600, flag: 'wx' });
  const snapshot = join(root, 'ticket-prompt.json');
  writeFileSync(snapshot, approvedBytes, { mode: 0o600, flag: 'wx' });
  const env = { PATH: executablePath, HOME: root,
    IIAUTO_ISSUE_URL: `https://github.com/${task.repository}/issues/${task.issueNumber}`,
    IIAUTO_STREAM_ID: `github:${task.repository}#${task.issueNumber}`, IIAUTO_WORK_ROOT: root,
    IIAUTO_TICKET_PROMPT_FILE: snapshot, IIAUTO_TICKET_PROMPT_SHA256: approvedDigest,
    IIAUTO_REPOSITORY_ID: String(task.repositoryId), IIAUTO_PROJECT_ITEM_ID: task.projectItemId,
    IIAUTO_PERMISSION_PROFILE: `${profile.id}@${profile.version}`,
    IIAUTO_ALLOWED_ACTIONS_JSON: runtime.canonicalJson(profile.allowed_actions), IIAUTO_DENIED_ACTIONS_JSON: runtime.canonicalJson(profile.denied_actions),
    IIAUTO_RESULT_FILE: join(root, 'result.json'), IIAUTO_DEFER_GITHUB_MUTATIONS: '1',
    IIAUTO_GITHUB_APP_SLUG: task.appSlug, IIAUTO_AUTOMATION_ALLOWED_APP_SLUGS: task.appSlug,
    IIAUTO_DISPATCH_ID: task.dispatchId,
  };
  try {
    const program = join(root, 'prepare.sh');
    writeFileSync(program, ['set -euo pipefail', sources.core, sources.status.replace(resultPlaceholder, quote(join(root, 'result.json'))),
      'gh() { return 125; }', 'curl() { return 125; }', policy, ''].join('\n'), { mode: 0o600, flag: 'wx' });
    await runtime.runTrustedProcess({ command: '/bin/bash', args: [program], cwd: root, env, timeoutMs: 15000, maxOutputBytes: 65536, ...(signal ? { signal } : {}) });
    const text = readFileSync(join(root, 'prompt.md'));
    if (!text.length || text.length > 120000) throw Error('prepared-prompt-limit');
    return { text: text.toString('utf8'), sha256: digest(text), approvedDigest,
      components: ['core', 'status', 'prepare'].map(name => ({ name: 'prompt-helper-' + name, version: 'sha256:' + helpers[name].sha256 })) };
  } catch { throw Error('existing-prompt-preparation-failed'); }
  finally {
    if (realpathSync(root) !== root || readFileSync(join(root, '.owner'), 'utf8') !== owner) throw Error('prompt-preparation-cleanup-unconfirmed');
    rmSync(root, { recursive: true });
  }
}
