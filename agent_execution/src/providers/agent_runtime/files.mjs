/** Bounded binary transfer through the runtime's existing worker transport. */
export async function workerSession(worker, request, input = Buffer.alloc(0)) {
  if (typeof worker.open !== 'function') throw Error('worker-duplex-unavailable');
  const session = await worker.open(request), chunks = [];
  try {
    const output = (async () => { for await (const chunk of session.output) chunks.push(Buffer.from(chunk)); })();
    void output.catch(() => {});
    await session.write(input); session.end();
    await output;
    const completion = await session.completion;
    if (completion.exitCode !== 0) throw Error('worker-transfer-failed');
    return Buffer.concat(chunks);
  } finally { await session.close(); }
}

export async function writeWorkerFile(worker, path, value, context) {
  if (!Buffer.isBuffer(value) || value.length > 16777216) throw Error('worker-file-input-limit');
  const program = `import os,sys
value=sys.stdin.buffer.read(16777217)
if len(value)>16777216: raise ValueError('input-limit')
fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
with os.fdopen(fd,'wb') as out: out.write(value)
`;
  await workerSession(worker, { command: '/usr/bin/python3', args: ['-c', program, path], ...context,
    maxInputBytes: Math.max(1, value.length), maxOutputBytes: 65536 }, value);
}

export async function readWorkerFile(worker, path, maximum, context) {
  if (!Number.isSafeInteger(maximum) || maximum < 1 || maximum > 67108864) throw Error('worker-file-output-limit');
  const program = `import os,stat,sys
fd=os.open(sys.argv[1],os.O_RDONLY|os.O_NOFOLLOW)
with os.fdopen(fd,'rb') as source:
 before=os.fstat(source.fileno())
 if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_size>int(sys.argv[2]): raise ValueError('file-limit')
 while True:
  chunk=source.read(65536)
  if not chunk: break
  sys.stdout.buffer.write(chunk)
 after=os.fstat(source.fileno())
 if (before.st_size,before.st_mtime_ns,before.st_ctime_ns)!=(after.st_size,after.st_mtime_ns,after.st_ctime_ns): raise ValueError('file-changed')
`;
  return workerSession(worker, { command: '/usr/bin/python3', args: ['-c', program, path, String(maximum)], ...context,
    maxInputBytes: 1, maxOutputBytes: maximum });
}
