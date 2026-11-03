(function installIiFfmpegUniversalBridge(global) {
  'use strict';

  if (global.IiFfmpegUniversalBridge) return;

  const engines = new Map();
  const scriptLoads = new Map();

  function bytesToHex(bytes) {
    return Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
  }

  const maxClientScriptBytes = 2 * 1024 * 1024;

  async function fetchVerified(url, expectedSha256, maxBytes) {
    if (!/^[0-9a-f]{64}$/.test(expectedSha256 || '')) {
      throw new Error('A pinned SHA-256 is required for every browser engine asset.');
    }
    const response = await fetch(url, {
      cache: 'no-store',
      credentials: 'same-origin',
      redirect: 'error',
    });
    if (!response.ok) {
      throw new Error(`Unable to fetch pinned browser engine asset: ${url}`);
    }
    const declared = Number(response.headers?.get?.('content-length'));
    if (Number.isFinite(declared) && declared > maxBytes) {
      throw new Error(`Browser engine asset exceeds its byte limit: ${url}`);
    }
    const reader = response.body?.getReader?.();
    if (!reader) {
      throw new Error(`Browser engine asset has no bounded byte stream: ${url}`);
    }
    const chunks = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!(value instanceof Uint8Array) || total + value.byteLength > maxBytes) {
        await reader.cancel();
        throw new Error(`Browser engine asset exceeds its byte limit: ${url}`);
      }
      chunks.push(value);
      total += value.byteLength;
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const digest = bytesToHex(
      new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    );
    if (digest !== expectedSha256) {
      throw new Error(`Browser engine asset failed SHA-256 verification: ${url}`);
    }
    return bytes;
  }

  function loadScript(url, expectedSha256) {
    const key = `${url}#${expectedSha256}`;
    if (scriptLoads.has(key)) return scriptLoads.get(key);
    const load = fetchVerified(url, expectedSha256, maxClientScriptBytes).then(
      (bytes) => new Promise((resolve, reject) => {
        const blobUrl = URL.createObjectURL(
          new Blob([bytes], { type: 'text/javascript' }),
        );
        const script = document.createElement('script');
        script.src = blobUrl;
        script.async = true;
        script.addEventListener(
          'load',
          () => {
            URL.revokeObjectURL(blobUrl);
            const Constructor = global.FFmpegWASM?.FFmpeg;
            if (Constructor) {
              // Capture the constructor at the verified script's load event.
              // The global registration is mutable and may subsequently be
              // replaced by another independently verified bundle.
              resolve(Constructor);
            } else {
              script.remove();
              reject(new Error(`ffmpeg.wasm script did not expose FFmpeg: ${url}`));
            }
          },
          { once: true },
        );
        script.addEventListener(
          'error',
          () => {
            URL.revokeObjectURL(blobUrl);
            script.remove();
            reject(new Error(`Unable to load ffmpeg.wasm script: ${url}`));
          },
          { once: true },
        );
        document.head.appendChild(script);
      }),
    );
    const tracked = load.catch((error) => {
      if (scriptLoads.get(key) === tracked) scriptLoads.delete(key);
      throw error;
    });
    scriptLoads.set(key, tracked);
    return tracked;
  }

  global.IiFfmpegUniversalBridge = Object.freeze({
    async create(id, config, onLog, onProgress) {
      if (engines.has(id)) return;
      let rejectCancellation;
      const cancellation = new Promise((_, reject) => {
        rejectCancellation = reject;
      });
      const record = {
        engine: null,
        cancelled: false,
        quotaExceeded: false,
        cancel() {
          if (record.cancelled) return;
          record.cancelled = true;
          rejectCancellation(new Error('FFmpeg load was cancelled.'));
        },
      };
      engines.set(id, record);
      try {
        const Constructor = await Promise.race([
          loadScript(config.ffmpegScriptUrl, config.ffmpegScriptSha256),
          cancellation,
        ]);
        if (record.cancelled) throw new Error('FFmpeg load was cancelled.');
        if (typeof Constructor !== 'function') {
          throw new Error('The verified ffmpeg.wasm constructor is unavailable.');
        }
        const engine = new Constructor();
        record.engine = engine;
        engine.on('log', ({ type, message }) => {
          if (message === 'II_FFMPEG_WORKSPACE_QUOTA_EXCEEDED') {
            record.quotaExceeded = true;
            return;
          }
          onLog(type || '', message || '');
        });
        engine.on('progress', ({ progress, time }) => onProgress(progress, time));
        const loadConfig = {
          classWorkerURL: config.classWorkerUrl,
          coreURL: config.coreScriptUrl,
          iiCoreScriptSha256: config.coreScriptSha256,
          wasmURL: config.coreWasmUrl,
          iiCoreWasmSha256: config.coreWasmSha256,
          iiWorkspaceLimitBytes: config.workspaceLimitBytes,
          iiReadLimitBytes: config.readLimitBytes,
          iiEngineMemoryLimitBytes: config.engineMemoryLimitBytes,
        };
        await Promise.race([engine.load(loadConfig), cancellation]);
        if (record.cancelled) throw new Error('FFmpeg load was cancelled.');
      } catch (error) {
        record.engine?.terminate();
        engines.delete(id);
        throw error;
      }
    },

    async writeFile(id, name, bytes) {
      await engines.get(id).engine.writeFile(name, bytes);
    },

    async exec(id, argumentsList, timeoutMs, ffprobe) {
      const record = engines.get(id);
      const engine = record.engine;
      record.quotaExceeded = false;
      let timedOut = false;
      let timer;
      const execution = (ffprobe
        ? engine.ffprobe(argumentsList)
        : engine.exec(argumentsList)
      ).then((exitCode) => ({
        exitCode,
        timedOut: false,
        quotaExceeded: record.quotaExceeded,
      })).catch((error) => {
        if (timedOut) {
          return { exitCode: 1, timedOut: true, quotaExceeded: false };
        }
        if (record.quotaExceeded ||
            String(error).includes('workspace quota exceeded')) {
          return { exitCode: 1, timedOut: false, quotaExceeded: true };
        }
        throw error;
      });
      const timeout = new Promise((resolve) => {
        timer = setTimeout(() => {
          timedOut = true;
          record.cancelled = true;
          engine.terminate();
          engines.delete(id);
          resolve({ exitCode: 1, timedOut: true, quotaExceeded: false });
        }, timeoutMs);
      });
      try {
        return await Promise.race([execution, timeout]);
      } finally {
        clearTimeout(timer);
      }
    },

    async readFileBounded(id, name, maxBytes, includeBytes) {
      const engine = engines.get(id).engine;
      const entry = (await engine.listDir('.')).find(
        (candidate) => candidate.name === name && !candidate.isDir,
      );
      if (entry && Number.isSafeInteger(entry.size) && entry.size > maxBytes) {
        return {
          bytes: new Uint8Array(0),
          byteLength: entry.size,
          tooLarge: true,
        };
      }
      if (!entry || !Number.isSafeInteger(entry.size) || entry.size < 0) {
        throw new Error(`FFmpeg output has no trustworthy size: ${name}`);
      }
      if (!includeBytes) {
        return {
          bytes: new Uint8Array(0),
          byteLength: entry.size,
          tooLarge: false,
        };
      }
      const bytes = await engine.readFile(name);
      if (!(bytes instanceof Uint8Array)) {
        throw new Error(`FFmpeg output is not binary: ${name}`);
      }
      if (bytes.byteLength > maxBytes) {
        return {
          bytes: new Uint8Array(0),
          byteLength: bytes.byteLength,
          tooLarge: true,
        };
      }
      return { bytes, byteLength: bytes.byteLength, tooLarge: false };
    },

    async deleteFile(id, name) {
      const engine = engines.get(id)?.engine;
      if (!engine) return;
      try {
        await engine.deleteFile(name);
      } catch (_) {
        // Cleanup is idempotent. The engine may already be terminated.
      }
    },

    terminate(id) {
      const record = engines.get(id);
      if (!record) return;
      record.cancel();
      record.engine?.terminate();
      engines.delete(id);
    },
  });
})(globalThis);
