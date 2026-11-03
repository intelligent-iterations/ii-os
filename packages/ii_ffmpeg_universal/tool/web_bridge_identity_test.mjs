import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const encoder = new TextEncoder();

const bridgeSource = fs.readFileSync(
  new URL('../assets/web/ii_ffmpeg_universal_bridge.js', import.meta.url),
  'utf8',
);

const wrappers = {
  '/wrapper-a.js': `globalThis.FFmpegWASM = { FFmpeg: class {
    constructor() { globalThis.constructed.push('a'); }
    on() {}
    async load() {}
    terminate() {}
  } };`,
  '/wrapper-b.js': `globalThis.FFmpegWASM = { FFmpeg: class {
    constructor() { globalThis.constructed.push('b'); }
    on() {}
    async load() {}
    terminate() {}
  } };`,
};

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function createHarness(delays = {}) {
  const blobs = new Map();
  let nextBlob = 0;
  let context;
  const document = {
    createElement: () => {
      const listeners = new Map();
      return {
        addEventListener(name, callback) {
          listeners.set(name, callback);
        },
        remove() {},
        async dispatch() {
          try {
            const source = await blobs.get(this.src).text();
            vm.runInContext(source, context);
            listeners.get('load')();
          } catch (_) {
            listeners.get('error')();
          }
        },
      };
    },
    head: {
      appendChild(script) {
        setTimeout(() => script.dispatch(), delays[script.src] ?? 0);
      },
    },
  };
  context = vm.createContext({
    Blob,
    console,
    constructed: [],
    crypto: webcrypto,
    document,
    fetch: async (url) => {
      const bytes = encoder.encode(wrappers[url]);
      let delivered = false;
      return {
        ok: true,
        headers: { get: () => String(bytes.byteLength) },
        body: {
          getReader: () => ({
            async read() {
              if (delivered) return { done: true };
              delivered = true;
              return { done: false, value: bytes };
            },
            async cancel() {},
          }),
        },
      };
    },
    setTimeout,
    clearTimeout,
    URL: {
      createObjectURL(blob) {
        const id = `blob:${nextBlob++}`;
        blobs.set(id, blob);
        return id;
      },
      revokeObjectURL(id) {
        blobs.delete(id);
      },
    },
    Uint8Array,
  });
  vm.runInContext(bridgeSource, context);
  return context;
}

function configuration(path) {
  return {
    ffmpegScriptUrl: path,
    ffmpegScriptSha256: digest(wrappers[path]),
    classWorkerUrl: '/worker.js',
    coreScriptUrl: '/core.js',
    coreScriptSha256: '0'.repeat(64),
    coreWasmUrl: '/core.wasm',
    coreWasmSha256: '1'.repeat(64),
    workspaceLimitBytes: 1024,
    readLimitBytes: 1024,
    engineMemoryLimitBytes: 1024,
  };
}

test('cached wrapper digest remains bound after a different wrapper loads', async () => {
  const context = createHarness();
  const bridge = context.IiFfmpegUniversalBridge;
  await bridge.create('a-first', configuration('/wrapper-a.js'), () => {}, () => {});
  await bridge.create('b', configuration('/wrapper-b.js'), () => {}, () => {});
  await bridge.create('a-cached', configuration('/wrapper-a.js'), () => {}, () => {});
  assert.deepEqual([...context.constructed], ['a', 'b', 'a']);
});

test('concurrent verified wrappers instantiate their captured constructors', async () => {
  const context = createHarness({'blob:0': 5, 'blob:1': 0});
  const bridge = context.IiFfmpegUniversalBridge;
  await Promise.all([
    bridge.create('a', configuration('/wrapper-a.js'), () => {}, () => {}),
    bridge.create('b', configuration('/wrapper-b.js'), () => {}, () => {}),
  ]);
  assert.deepEqual(new Set(context.constructed), new Set(['a', 'b']));
});
