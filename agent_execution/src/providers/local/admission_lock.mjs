import { spawnSync } from 'node:child_process';
import { closeSync, constants, fstatSync, lstatSync, openSync } from 'node:fs';

// flock belongs to the open-file description inherited on fd 3. The helper
// exits immediately, while this process retains the locked description until
// close (including SIGKILL/OOM). No child remains alive to strand the lock.
const acquire = 'import fcntl\ntry: fcntl.flock(3, fcntl.LOCK_EX | fcntl.LOCK_NB)\nexcept BlockingIOError: raise SystemExit(73)';

/** Local shared-volume transaction lock; no PID, clock or reservation expiry. */
export function withAdmissionLock(path, action) {
  let fd;
  try { fd = openSync(path, constants.O_RDWR | constants.O_CREAT | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o600); }
  catch { throw Error('admission-lock-unsafe-or-legacy'); }
  try {
    const before = fstatSync(fd);
    if (!before.isFile() || before.uid !== process.getuid() || before.nlink !== 1 ||
        (before.mode & 0o077) || before.size !== 0) throw Error('admission-lock-unsafe');
    const result = spawnSync('/usr/bin/python3', ['-I', '-c', acquire], {
      stdio: ['ignore', 'ignore', 'pipe', fd], env: { PATH: '/usr/bin:/bin' }, timeout: 5000, maxBuffer: 4096,
    });
    if (result.status === 73) throw Error('admission-busy');
    if (result.error || result.status !== 0) throw Error('admission-lock-unavailable');
    const current = lstatSync(path);
    if (!current.isFile() || current.isSymbolicLink() || current.dev !== before.dev || current.ino !== before.ino) throw Error('admission-lock-ownership-changed');
    // Never unlink the persistent inode: that would let a second process lock
    // another inode while this transaction is still running.
    return action();
  } finally { closeSync(fd); }
}
