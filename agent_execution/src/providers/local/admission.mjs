import { closeSync, constants, fstatSync, fsyncSync, lstatSync, openSync, readFileSync, readdirSync, realpathSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';
import { withAdmissionLock } from './admission_lock.mjs';

function writeDurable(path, value, replace = false) {
  const temporary = replace ? path + '.' + randomUUID() : path;
  const fd = openSync(temporary, 'wx', 0o600);
  try { writeFileSync(fd, JSON.stringify(value)); fsyncSync(fd); } finally { closeSync(fd); }
  if (replace) renameSync(temporary, path);
}
function syncDirectory(path) {
  const fd = openSync(path, 'r');
  try { fsyncSync(fd); } finally { closeSync(fd); }
}
function readRecord(path) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 || (stat.mode & 0o077) || stat.size > 65536) throw Error('unsafe-admission-record');
    return JSON.parse(readFileSync(fd, 'utf8'));
  } finally { closeSync(fd); }
}
function resources(value) {
  if (!value || !['cpu', 'memoryMiB', 'diskGiB'].every(key => Number.isSafeInteger(value[key]) && value[key] > 0) || Object.keys(value).length !== 3) throw Error('invalid-reservation-resources');
  return { cpu: value.cpu, memoryMiB: value.memoryMiB, diskGiB: value.diskGiB };
}
function identity(value) {
  if (!value || !['executionId', 'attemptId'].every(key => typeof value[key] === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(value[key])) ||
      !/^sha256:[a-f0-9]{64}$/.test(value.inputDigest)) throw Error('invalid-reservation-identity');
  return { executionId: value.executionId, attemptId: value.attemptId, inputDigest: value.inputDigest };
}

function policy(value) {
  if (!value || Object.keys(value).sort().join(',') !== 'agentId,maxConcurrent,maxRunsPerMonth,maxRunsPerSubject,subjectId,timeoutSeconds' ||
      !['agentId', 'subjectId'].every(key => typeof value[key] === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(value[key])) ||
      !['maxConcurrent', 'maxRunsPerSubject', 'maxRunsPerMonth', 'timeoutSeconds'].every(key => Number.isSafeInteger(value[key]) && value[key] > 0) ||
      value.timeoutSeconds > 7200) throw Error('invalid-admission-policy');
  return { agentId: value.agentId, subjectId: value.subjectId, maxConcurrent: value.maxConcurrent,
    maxRunsPerSubject: value.maxRunsPerSubject, maxRunsPerMonth: value.maxRunsPerMonth, timeoutSeconds: value.timeoutSeconds };
}

/** One explicitly partitioned, local execution allocation. Never a second whole-host ledger. */
export function openAdmission({ directory, allocationId, capacity, monthlyLimit, clock = () => new Date() }) {
  const root = resolve(directory), stat = lstatSync(root);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) || realpathSync(root) !== root) throw Error('unsafe-admission-directory');
  if (typeof allocationId !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(allocationId)) throw Error('invalid-allocation');
  if (!Number.isSafeInteger(monthlyLimit) || monthlyLimit < 1 || monthlyLimit > 10000) throw Error('invalid-allocation-monthly-limit');
  const binding = { schemaVersion: 1, allocationId, capacity: resources(capacity), monthlyLimit };
  const lock = join(root, '.lock');
  function transaction(action) {
    return withAdmissionLock(lock, () => {
      const owner = join(root, 'allocation.json');
      try { writeDurable(owner, binding); syncDirectory(root); }
      catch (error) { if (error.code !== 'EEXIST') throw error; }
      if (JSON.stringify(readRecord(owner)) !== JSON.stringify(binding)) throw Error('allocation-binding-mismatch');
      return action();
    });
  }
  function pathFor(id) {
    // Retries of the same approved execution share one reservation even when
    // GitHub assigns another workflow attempt. They never get a second launch.
    return join(root, createHash('sha256').update(id.executionId).digest('hex') + '.json');
  }
  function records() {
    const names = readdirSync(root).filter(name => /^[a-f0-9]{64}\.json$/.test(name));
    if (names.length > 10000) throw Error('admission-retention-limit');
    return names.map(name => {
      const record = readRecord(join(root, name));
      identity(record); resources(record.resources); policy(record.policy);
      if (!Number.isFinite(Date.parse(record.createdAt)) || !Number.isFinite(Date.parse(record.expiresAt))) throw Error('invalid-admission-record');
      if (!['reserved', 'released'].includes(record.state) || record.allocationId !== allocationId) throw Error('invalid-admission-record');
      return record;
    });
  }
  return {
    reserve(request) {
      const id = identity(request), requested = resources(request.resources), requestedPolicy = policy(request.policy);
      return transaction(() => {
        const entries = records();
        const existing = entries.find(entry => entry.executionId === id.executionId);
        if (existing) {
          if (existing.inputDigest !== id.inputDigest || JSON.stringify(existing.resources) !== JSON.stringify(requested) || JSON.stringify(existing.policy) !== JSON.stringify(requestedPolicy)) throw Error('execution-reservation-conflict');
          return { disposition: 'recover', reservation: existing };
        }
        const now = clock();
        if (!(now instanceof Date) || !Number.isFinite(now.getTime())) throw Error('invalid-admission-clock');
        const monthStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
        const monthly = entries.filter(entry => Date.parse(entry.expiresAt) >= monthStart);
        if (monthly.length >= monthlyLimit) return { disposition: 'denied', reason: 'allocation-monthly-limit' };
        const agent = entries.filter(entry => entry.policy.agentId === requestedPolicy.agentId);
        if (agent.filter(entry => Date.parse(entry.expiresAt) >= monthStart).length >= requestedPolicy.maxRunsPerMonth) return { disposition: 'denied', reason: 'agent-monthly-limit' };
        if (agent.filter(entry => entry.policy.subjectId === requestedPolicy.subjectId).length >= requestedPolicy.maxRunsPerSubject) return { disposition: 'denied', reason: 'subject-limit' };
        if (agent.some(entry => entry.state === 'reserved' && entry.policy.subjectId === requestedPolicy.subjectId)) return { disposition: 'waiting-for-capacity' };
        if (agent.filter(entry => entry.state === 'reserved').length >= requestedPolicy.maxConcurrent) return { disposition: 'waiting-for-capacity' };
        for (const key of Object.keys(requested)) {
          const allocated = entries.filter(entry => entry.state === 'reserved').reduce((sum, entry) => sum + entry.resources[key], 0);
          if (allocated + requested[key] > binding.capacity[key]) return { disposition: 'waiting-for-capacity' };
        }
        const record = { schemaVersion: 1, allocationId, ...id, resources: requested,
          state: 'reserved', reservationId: randomUUID(), policy: requestedPolicy, createdAt: now.toISOString(),
          expiresAt: new Date(now.getTime() + requestedPolicy.timeoutSeconds * 1000 + 360000).toISOString() };
        writeDurable(pathFor(id), record); syncDirectory(root);
        return { disposition: 'launch', reservation: record };
      });
    },
    reserveObservation(request) {
      const id = identity(request);
      return transaction(() => {
        const pendingPath = join(root, '.observations-pending.json');
        try { readRecord(pendingPath); throw Error('observation-budget-recovery-required'); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        const now = clock();
        if (!(now instanceof Date) || !Number.isFinite(now.getTime())) throw Error('invalid-admission-clock');
        const month = now.toISOString().slice(0, 7);
        const monthPath = join(root, `.observations-month-${month}.json`);
        const executionPath = join(root, `.observations-execution-${createHash('sha256').update(id.executionId).digest('hex')}.json`);
        function counter(path, initial) {
          try { return { value: readRecord(path), exists: true }; }
          catch (error) { if (error.code !== 'ENOENT') throw error; return { value: initial, exists: false }; }
        }
        const monthly = counter(monthPath, { schemaVersion: 1, allocationId, month, count: 0 });
        const execution = counter(executionPath, { schemaVersion: 1, allocationId, executionId: id.executionId, inputDigest: id.inputDigest, count: 0 });
        if ([monthly.value, execution.value].some(value => value.schemaVersion !== 1 || value.allocationId !== allocationId || !Number.isSafeInteger(value.count) || value.count < 0) ||
            monthly.value.month !== month || execution.value.executionId !== id.executionId || execution.value.inputDigest !== id.inputDigest) throw Error('observation-budget-binding-mismatch');
        if (execution.value.count >= 16) return { allowed: false, reason: 'execution-observation-limit' };
        if (monthly.value.count >= monthlyLimit * 16) return { allowed: false, reason: 'monthly-observation-limit' };
        // A crash between the two counters must never undercharge another
        // request. The durable marker blocks all further accounting until an
        // operator reconciles that exact interrupted transaction.
        const nonce = randomUUID();
        writeDurable(pendingPath, { schemaVersion: 1, nonce, allocationId, month,
          executionId: id.executionId, inputDigest: id.inputDigest,
          previousMonthly: monthly.value.count, previousExecution: execution.value.count });
        syncDirectory(root);
        writeDurable(monthPath, { ...monthly.value, count: monthly.value.count + 1 }, monthly.exists);
        writeDurable(executionPath, { ...execution.value, count: execution.value.count + 1 }, execution.exists);
        syncDirectory(root);
        if (readRecord(pendingPath).nonce !== nonce) throw Error('observation-budget-ownership-changed');
        unlinkSync(pendingPath); syncDirectory(root);
        return { allowed: true };
      });
    },
    release(reservation, receipt) {
      const id = identity(reservation);
      return transaction(() => {
        const path = pathFor(id), existing = readRecord(path);
        if (existing.reservationId !== reservation.reservationId || existing.inputDigest !== id.inputDigest || existing.attemptId !== id.attemptId) throw Error('reservation-binding-mismatch');
        if (!receipt || receipt.executionId !== id.executionId || receipt.attemptId !== id.attemptId || receipt.inputDigest !== id.inputDigest || receipt.cleanupConfirmed !== true ||
            !Array.isArray(receipt.cleanup) || !receipt.cleanup.some(item => item.component === 'runtime' && item.confirmed === true) ||
            receipt.cleanup.some(item => item.confirmed !== true)) throw Error('cleanup-proof-required');
        if (existing.state === 'released') return existing;
        const released = { ...existing, state: 'released', releasedAt: new Date().toISOString(),
          cleanupDigest: createHash('sha256').update(JSON.stringify(receipt)).digest('hex') };
        writeDurable(path, released, true); syncDirectory(root);
        return released;
      });
    },
  };
}
