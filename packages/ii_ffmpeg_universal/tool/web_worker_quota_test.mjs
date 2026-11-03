import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const workerSource = fs.readFileSync(
  new URL('../assets/web/ii_ffmpeg_universal_worker.js', import.meta.url),
  'utf8',
);

test('verified core fetch rejects redirects before reading bytes', async () => {
  let observedOptions;
  let delivered = false;
  const context = vm.createContext({
    crypto: webcrypto,
    fetch: async (_url, options) => {
      observedOptions = options;
      return {
        ok: true,
        headers: { get: () => '0' },
        body: {
          getReader: () => ({
            async read() {
              if (delivered) return { done: true };
              delivered = true;
              return { done: false, value: new Uint8Array(0) };
            },
            async cancel() {},
          }),
        },
      };
    },
    self: { postMessage: () => {} },
    Uint8Array,
  });
  vm.runInContext(workerSource, context);
  await vm.runInContext(
    "fetchVerified('https://example.test/core.js', " +
      "'e3b0c44298fc1c149afbf4c8996fb924" +
      "27ae41e4649b934ca495991b7852b855', 1)",
    context,
  );
  assert.equal(observedOptions.redirect, 'error');
  assert.equal(observedOptions.credentials, 'same-origin');
});

test('verified core fetch cancels before a streamed byte ceiling is crossed', async () => {
  let cancelled = false;
  let delivered = false;
  const context = vm.createContext({
    crypto: webcrypto,
    fetch: async () => ({
      ok: true,
      headers: { get: () => null },
      body: {
        getReader: () => ({
          async read() {
            if (delivered) return { done: true };
            delivered = true;
            return { done: false, value: new Uint8Array(5) };
          },
          async cancel() {
            cancelled = true;
          },
        }),
      },
    }),
    self: { postMessage: () => {} },
    Uint8Array,
  });
  vm.runInContext(workerSource, context);
  await assert.rejects(
    vm.runInContext(
      "fetchVerified('/core.wasm', '0'.repeat(64), 4)",
      context,
    ),
    /exceeds its byte limit/,
  );
  assert.equal(cancelled, true);
});

test('production worker has no derived core-worker escape', () => {
  assert.doesNotMatch(workerSource, /resolvedWorker/);
  assert.match(workerSource, /Unverified pthread workers are forbidden/);
});

function quotaHarness(limit) {
  const write = (stream, _buffer, _offset, length, position) => {
    stream.node.usedBytes = Math.max(stream.node.usedBytes, position + length);
    return length;
  };
  const allocate = (stream, offset, length) => {
    stream.node.usedBytes = Math.max(stream.node.usedBytes, offset + length);
  };
  const setattr = (node, attributes) => {
    if (attributes.size !== undefined) node.usedBytes = attributes.size;
  };
  const fileStream = { write, allocate };
  const fileNode = { setattr };
  const memfs = {
    stream_ops: { write, allocate },
    node_ops: { setattr },
    ops_table: {
      file: {
        stream: fileStream,
        node: fileNode,
      },
    },
  };
  memfs.stream_ops.msync = (stream, buffer, offset, length) =>
    memfs.stream_ops.write(stream, buffer, 0, length, offset, false);
  const logs = [];
  const context = vm.createContext({
    self: {
      postMessage: (message) => logs.push(message),
    },
    testFfmpeg: {
      FS: {
        filesystems: { MEMFS: memfs },
        stat: () => ({ size: 0 }),
        unlink: () => {},
      },
    },
  });
  vm.runInContext(workerSource, context);
  vm.runInContext(
    `ffmpeg = testFfmpeg; workspaceLimitBytes = ${limit};
     workspaceBytes = 0; installQuotaFileSystem();`,
    context,
  );
  return { context, fileNode, fileStream, logs, memfs };
}

function invoke(context, body) {
  context.testNode = { usedBytes: 0 };
  vm.runInContext(
    `testStream = {node: testNode, position: 0}; ${body}`,
    context,
  );
  return context.testNode.usedBytes;
}

test('low-level MEMFS write and msync path reject before quota overflow', () => {
  const { context, logs, memfs } = quotaHarness(4);
  context.testWrite = memfs.stream_ops.write;
  assert.throws(
    () => invoke(context, 'testWrite(testStream, new Uint8Array(5), 0, 5, 0, false);'),
    /workspace quota exceeded/,
  );
  assert.equal(context.testNode.usedBytes, 0);
  assert.equal(logs.at(-1).data.message, 'II_FFMPEG_WORKSPACE_QUOTA_EXCEEDED');
  context.testMsync = memfs.stream_ops.msync;
  assert.throws(
    () => invoke(context, 'testMsync(testStream, new Uint8Array(5), 0, 5, 0);'),
    /workspace quota exceeded/,
  );
  assert.equal(context.testNode.usedBytes, 0);
});

test('copied stream allocate operation rejects before quota overflow', () => {
  const { context, fileStream } = quotaHarness(4);
  context.testAllocate = fileStream.allocate;
  assert.throws(
    () => invoke(context, 'testAllocate(testStream, 0, 5);'),
    /workspace quota exceeded/,
  );
  assert.equal(context.testNode.usedBytes, 0);
});

test('copied node setattr operation covers truncate and ftruncate', () => {
  const { context, fileNode } = quotaHarness(4);
  context.testSetattr = fileNode.setattr;
  assert.throws(
    () => invoke(context, 'testSetattr(testNode, {size: 5});'),
    /workspace quota exceeded/,
  );
  assert.equal(context.testNode.usedBytes, 0);
});

test('shrink releases logical workspace capacity for a later write', () => {
  const { context, fileNode, fileStream } = quotaHarness(6);
  context.testSetattr = fileNode.setattr;
  context.testWrite = fileStream.write;
  context.testNode = { usedBytes: 0 };
  vm.runInContext(
    `testStream = {node: testNode, position: 0};
     testWrite(testStream, new Uint8Array(6), 0, 6, 0, false);
     testSetattr(testNode, {size: 2});
     testWrite(testStream, new Uint8Array(4), 0, 4, 2, false);`,
    context,
  );
  assert.equal(context.testNode.usedBytes, 6);
});

test('ffprobe consumes the verified core wrapper return code', () => {
  const calls = [];
  const context = vm.createContext({
    self: { postMessage: () => {} },
    testFfmpeg: {
      ret: -1,
      setTimeout: (value) => calls.push(['timeout', value]),
      ffprobe: (...values) => {
        calls.push(['ffprobe', ...values]);
        return 0;
      },
      reset: () => calls.push(['reset']),
    },
  });
  vm.runInContext(workerSource, context);
  const result = vm.runInContext(
    `ffmpeg = testFfmpeg;
     ffprobe({args: ['-i', 'input.mp4'], timeout: 2500});`,
    context,
  );
  assert.equal(result, 0);
  assert.deepEqual(calls, [
    ['timeout', 2500],
    ['ffprobe', '-i', 'input.mp4'],
    ['reset'],
  ]);
});

test('ffprobe preserves a real native failure code', () => {
  const context = vm.createContext({
    self: { postMessage: () => {} },
    testFfmpeg: {
      ret: -1,
      setTimeout: () => {},
      ffprobe: () => 1,
      reset: () => {},
    },
  });
  vm.runInContext(workerSource, context);
  const result = vm.runInContext(
    `ffmpeg = testFfmpeg; ffprobe({args: ['invalid.mp4']});`,
    context,
  );
  assert.equal(result, 1);
});
