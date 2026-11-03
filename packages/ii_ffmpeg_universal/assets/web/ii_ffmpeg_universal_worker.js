// Adapted from @ffmpeg/ffmpeg 0.12.15 dist/esm/worker.js (MIT).
// Copyright (c) 2019 Jerome Wu.
// II changes add pre-write MEMFS quotas and pre-read size rejection.
/// <reference no-default-lib="true" />
/// <reference lib="esnext" />
/// <reference lib="webworker" />

const FFMessageType = Object.freeze({
  LOAD: 'LOAD',
  EXEC: 'EXEC',
  FFPROBE: 'FFPROBE',
  WRITE_FILE: 'WRITE_FILE',
  READ_FILE: 'READ_FILE',
  DELETE_FILE: 'DELETE_FILE',
  RENAME: 'RENAME',
  CREATE_DIR: 'CREATE_DIR',
  LIST_DIR: 'LIST_DIR',
  DELETE_DIR: 'DELETE_DIR',
  ERROR: 'ERROR',
  PROGRESS: 'PROGRESS',
  LOG: 'LOG',
  MOUNT: 'MOUNT',
  UNMOUNT: 'UNMOUNT',
});

let ffmpeg;
let workspaceLimitBytes = 192 * 1024 * 1024;
let readLimitBytes = 64 * 1024 * 1024;
let workspaceBytes = 0;
const maxCoreScriptBytes = 5 * 1024 * 1024;
const maxCoreWasmBytes = 64 * 1024 * 1024;

function bytesToHex(bytes) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
}

async function fetchVerified(url, expectedSha256, maxBytes) {
  if (!/^[0-9a-f]{64}$/.test(expectedSha256 || '')) {
    throw new Error('A pinned SHA-256 is required for every ffmpeg.wasm core asset.');
  }
  const response = await fetch(url, {
    cache: 'no-store',
    credentials: 'same-origin',
    redirect: 'error',
  });
  if (!response.ok) throw new Error(`Unable to fetch pinned core asset: ${url}`);
  const declared = Number(response.headers?.get?.('content-length'));
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new Error(`ffmpeg.wasm core asset exceeds its byte limit: ${url}`);
  }
  const reader = response.body?.getReader?.();
  if (!reader) {
    throw new Error(`ffmpeg.wasm core asset has no bounded byte stream: ${url}`);
  }
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!(value instanceof Uint8Array) || total + value.byteLength > maxBytes) {
      await reader.cancel();
      throw new Error(`ffmpeg.wasm core asset exceeds its byte limit: ${url}`);
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
    throw new Error(`ffmpeg.wasm core asset failed SHA-256 verification: ${url}`);
  }
  return bytes;
}

function positiveSafeInteger(value, fallback) {
  return Number.isSafeInteger(value) && value > 0 ? value : fallback;
}

function installQuotaFileSystem() {
  const fs = ffmpeg.FS;
  const memfs = fs.filesystems.MEMFS;
  const originalWrite = memfs.stream_ops.write;
  const originalAllocate = memfs.stream_ops.allocate;
  const originalSetattr = memfs.node_ops.setattr;
  const originalUnlink = fs.unlink.bind(fs);

  const quotaError = () => {
    self.postMessage({
      type: FFMessageType.LOG,
      data: {
        type: 'error',
        message: 'II_FFMPEG_WORKSPACE_QUOTA_EXCEEDED',
      },
    });
    throw new Error('FFmpeg MEMFS workspace quota exceeded.');
  };

  const validateResize = (node, nextBytes) => {
    const previousBytes = Number.isSafeInteger(node?.usedBytes)
      ? node.usedBytes
      : 0;
    if (!Number.isSafeInteger(nextBytes) || nextBytes < 0 ||
        workspaceBytes - previousBytes + nextBytes > workspaceLimitBytes) {
      quotaError();
    }
    return previousBytes;
  };

  const accountResize = (node, previousBytes, fallbackBytes) => {
    const actualBytes = Number.isSafeInteger(node?.usedBytes)
      ? node.usedBytes
      : fallbackBytes;
    workspaceBytes += actualBytes - previousBytes;
  };

  const quotaWrite = (stream, buffer, offset, length, position, canOwn) => {
    const node = stream?.node;
    const writePosition = Number.isSafeInteger(position)
      ? position
      : Number.isSafeInteger(stream?.position)
        ? stream.position
        : 0;
    const currentBytes = Number.isSafeInteger(node?.usedBytes)
      ? node.usedBytes
      : 0;
    const nextBytes = Math.max(currentBytes, writePosition + length);
    const previousBytes = validateResize(node, nextBytes);
    const written = originalWrite(
      stream,
      buffer,
      offset,
      length,
      position,
      canOwn,
    );
    accountResize(node, previousBytes, nextBytes);
    return written;
  };

  const quotaAllocate = (stream, offset, length) => {
    const nextBytes = Math.max(stream.node.usedBytes, offset + length);
    const previousBytes = validateResize(stream.node, nextBytes);
    const result = originalAllocate(stream, offset, length);
    accountResize(stream.node, previousBytes, nextBytes);
    return result;
  };

  const quotaSetattr = (node, attributes) => {
    if (attributes.size === undefined) return originalSetattr(node, attributes);
    const previousBytes = validateResize(node, attributes.size);
    const result = originalSetattr(node, attributes);
    accountResize(node, previousBytes, attributes.size);
    return result;
  };

  // Patch MEMFS below the public FS facade. FFmpeg reaches these operations
  // through write, pwrite, allocate, truncate/ftruncate, and mmap/msync.
  memfs.stream_ops.write = quotaWrite;
  memfs.stream_ops.allocate = quotaAllocate;
  memfs.node_ops.setattr = quotaSetattr;
  memfs.ops_table.file.stream.write = quotaWrite;
  memfs.ops_table.file.stream.allocate = quotaAllocate;
  memfs.ops_table.file.node.setattr = quotaSetattr;

  fs.unlink = (path) => {
    let removedBytes = 0;
    try {
      const stat = fs.stat(path);
      if (Number.isSafeInteger(stat.size)) removedBytes = stat.size;
    } catch (_) {
      // The original operation reports missing paths.
    }
    const result = originalUnlink(path);
    workspaceBytes = Math.max(0, workspaceBytes - removedBytes);
    return result;
  };
}

function selfTestQuotaFileSystem() {
  const fs = ffmpeg.FS;
  const memfs = fs.filesystems.MEMFS;
  const path = '__ii_ffmpeg_quota_self_test__';
  const productionLimit = workspaceLimitBytes;
  const productionBytes = workspaceBytes;
  let stream;
  try {
    fs.writeFile(path, new Uint8Array(0));
    stream = fs.open(path, 'w+');
    workspaceLimitBytes = 4;
    workspaceBytes = 0;
    const attempts = [
      () => memfs.stream_ops.write(
        stream,
        new Uint8Array(5),
        0,
        5,
        0,
        false,
      ),
      () => memfs.stream_ops.allocate(stream, 0, 5),
      () => memfs.node_ops.setattr(stream.node, { size: 5 }),
      () => memfs.stream_ops.msync(
        stream,
        new Uint8Array(5),
        0,
        5,
        0,
      ),
    ];
    for (const attempt of attempts) {
      let rejected = false;
      try {
        attempt();
      } catch (error) {
        rejected = String(error).includes('workspace quota exceeded');
      }
      if (!rejected || stream.node.usedBytes !== 0 || workspaceBytes !== 0) {
        throw new Error('The real MEMFS quota self-test failed closed.');
      }
    }
  } finally {
    if (stream) fs.close(stream);
    try {
      fs.unlink(path);
    } catch (_) {
      // A failed setup may not have created the self-test file.
    }
    workspaceLimitBytes = productionLimit;
    workspaceBytes = productionBytes;
  }
}

async function load({
  coreURL,
  wasmURL,
  iiWorkspaceLimitBytes,
  iiReadLimitBytes,
  iiCoreScriptSha256,
  iiCoreWasmSha256,
  iiEngineMemoryLimitBytes,
}) {
  const first = !ffmpeg;
  const coreBytes = await fetchVerified(
    coreURL,
    iiCoreScriptSha256,
    maxCoreScriptBytes,
  );
  const wasmBytes = await fetchVerified(
    wasmURL,
    iiCoreWasmSha256,
    maxCoreWasmBytes,
  );
  const engineMemoryLimitBytes = positiveSafeInteger(
    iiEngineMemoryLimitBytes,
    512 * 1024 * 1024,
  );
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const upstreamCore = decoder.decode(coreBytes);
  const heapFunction = 'function getHeapMax(){return 536870912}';
  const ffprobeFunction = 'function ffprobe(..._args){const args=[' +
    '...Module["DEFAULT_ARGS_FFPROBE"],..._args];try{' +
    'Module["_ffprobe"](args.length,stringsToPtr(args))}catch(e){' +
    'if(!e.message.startsWith("Aborted")){throw e}}return Module["ret"]}';
  const locateFunction = 'function _locateFile(path,prefix){const ' +
    'mainScriptUrlOrBlob=Module["mainScriptUrlOrBlob"];if(mainScriptUrlOrBlob)' +
    '{const{wasmURL:wasmURL,workerURL:workerURL}=JSON.parse(atob(' +
    'mainScriptUrlOrBlob.slice(mainScriptUrlOrBlob.lastIndexOf("#")+1)));' +
    'if(path.endsWith(".wasm"))return wasmURL;if(path.endsWith(' +
    '".worker.js"))return workerURL}return prefix+path}';
  if (upstreamCore.split(heapFunction).length !== 2 ||
      upstreamCore.split(ffprobeFunction).length !== 2 ||
      upstreamCore.split(locateFunction).length !== 2 ||
      upstreamCore.includes('ENVIRONMENT_IS_PTHREAD') ||
      upstreamCore.includes('SharedArrayBuffer') ||
      upstreamCore.includes('PThread')) {
    throw new Error(
      'The selected ffmpeg.wasm core is not the reviewed single-thread shape.',
    );
  }
  const boundedCore = upstreamCore
    .replace(
      heapFunction,
      'function getHeapMax(){return Math.min(' +
        'Module["iiHeapLimitBytes"],536870912)}',
    )
    .replace(
      ffprobeFunction,
      'function ffprobe(..._args){const args=[' +
        '...Module["DEFAULT_ARGS_FFPROBE"],..._args];let result;try{' +
        'result=Module["_ffprobe"](args.length,stringsToPtr(args))}catch(e){' +
        'if(!e.message.startsWith("Aborted")){throw e}' +
        'result=Module["ret"]}return result}',
    )
    .replace(
      locateFunction,
      'function _locateFile(path,prefix){const mainScriptUrlOrBlob=' +
        'Module["mainScriptUrlOrBlob"];if(mainScriptUrlOrBlob){const{' +
        'wasmURL:wasmURL}=JSON.parse(atob(mainScriptUrlOrBlob.slice(' +
        'mainScriptUrlOrBlob.lastIndexOf("#")+1)));if(path.endsWith(' +
        '".wasm"))return wasmURL;if(path.endsWith(".worker.js")){' +
        'throw new Error("Unverified pthread workers are forbidden")}}' +
        'return prefix+path}',
    );
  const coreBlobUrl = URL.createObjectURL(
    new Blob([boundedCore], { type: 'text/javascript' }),
  );
  try {
    const importedCore = await import(coreBlobUrl);
    self.createFFmpegCore = importedCore.default;
  } finally {
    URL.revokeObjectURL(coreBlobUrl);
  }
  if (!self.createFFmpegCore) {
    throw new Error('Unable to import the verified ffmpeg.wasm core.');
  }
  ffmpeg = await self.createFFmpegCore({
    mainScriptUrlOrBlob: `${coreURL}#${btoa(JSON.stringify({
      wasmURL: 'ii-verified-wasm-binary',
    }))}`,
    wasmBinary: new Uint8Array(wasmBytes),
    iiHeapLimitBytes: engineMemoryLimitBytes,
  });
  if (ffmpeg.HEAPU8.byteLength > engineMemoryLimitBytes) {
    throw new Error('The pinned ffmpeg.wasm core exceeds its memory boundary.');
  }
  if (typeof SharedArrayBuffer !== 'undefined' &&
      ffmpeg.HEAPU8.buffer instanceof SharedArrayBuffer) {
    throw new Error('Only a verified single-thread ffmpeg.wasm core is allowed.');
  }
  workspaceLimitBytes = positiveSafeInteger(
    iiWorkspaceLimitBytes,
    workspaceLimitBytes,
  );
  readLimitBytes = positiveSafeInteger(iiReadLimitBytes, readLimitBytes);
  workspaceBytes = 0;
  installQuotaFileSystem();
  selfTestQuotaFileSystem();
  ffmpeg.setLogger((data) => self.postMessage({
    type: FFMessageType.LOG,
    data,
  }));
  ffmpeg.setProgress((data) => self.postMessage({
    type: FFMessageType.PROGRESS,
    data,
  }));
  return first;
}

function exec({ args, timeout = -1 }) {
  ffmpeg.setTimeout(timeout);
  ffmpeg.exec(...args);
  const result = ffmpeg.ret;
  ffmpeg.reset();
  return result;
}

function ffprobe({ args, timeout = -1 }) {
  ffmpeg.setTimeout(timeout);
  let result;
  try {
    // During verified loading, the selected core's lossy upstream wrapper is
    // source-patched to return the exported native FFprobe status. This avoids
    // coupling the class worker itself to private module exports.
    result = ffmpeg.ffprobe(...args);
  } catch (error) {
    const message = String(error?.message || error);
    if (!message.startsWith('Aborted')) throw error;
    result = ffmpeg.ret;
  }
  ffmpeg.reset();
  if (!Number.isInteger(result)) {
    throw new Error('ffprobe returned an invalid native exit code.');
  }
  return result;
}

function readFile({ path, encoding }) {
  const stat = ffmpeg.FS.stat(path);
  if (!Number.isSafeInteger(stat.size) || stat.size > readLimitBytes) {
    throw new Error(`FFmpeg output exceeds the hard read quota: ${path}`);
  }
  return ffmpeg.FS.readFile(path, { encoding });
}

const handlers = {
  [FFMessageType.LOAD]: load,
  [FFMessageType.EXEC]: exec,
  [FFMessageType.FFPROBE]: ffprobe,
  [FFMessageType.WRITE_FILE]: ({ path, data }) => {
    ffmpeg.FS.writeFile(path, data);
    return true;
  },
  [FFMessageType.READ_FILE]: readFile,
  [FFMessageType.DELETE_FILE]: ({ path }) => {
    ffmpeg.FS.unlink(path);
    return true;
  },
  [FFMessageType.RENAME]: ({ oldPath, newPath }) => {
    ffmpeg.FS.rename(oldPath, newPath);
    return true;
  },
  [FFMessageType.CREATE_DIR]: ({ path }) => {
    ffmpeg.FS.mkdir(path);
    return true;
  },
  [FFMessageType.LIST_DIR]: ({ path }) => ffmpeg.FS.readdir(path).map((name) => {
    const stat = ffmpeg.FS.stat(`${path}/${name}`);
    return {
      name,
      isDir: ffmpeg.FS.isDir(stat.mode),
      size: stat.size,
    };
  }),
  [FFMessageType.DELETE_DIR]: ({ path }) => {
    ffmpeg.FS.rmdir(path);
    return true;
  },
  [FFMessageType.MOUNT]: ({ fsType, options, mountPoint }) => {
    const fileSystem = ffmpeg.FS.filesystems[String(fsType)];
    if (!fileSystem) return false;
    ffmpeg.FS.mount(fileSystem, options, mountPoint);
    return true;
  },
  [FFMessageType.UNMOUNT]: ({ mountPoint }) => {
    ffmpeg.FS.unmount(mountPoint);
    return true;
  },
};

self.onmessage = async ({ data: { id, type, data: request } }) => {
  const transfers = [];
  try {
    if (type !== FFMessageType.LOAD && !ffmpeg) {
      throw new Error('ffmpeg is not loaded.');
    }
    const handler = handlers[type];
    if (!handler) throw new Error(`Unknown ffmpeg worker message: ${type}`);
    const data = await handler(request);
    if (data instanceof Uint8Array) transfers.push(data.buffer);
    self.postMessage({ id, type, data }, transfers);
  } catch (error) {
    self.postMessage({
      id,
      type: FFMessageType.ERROR,
      data: String(error),
    });
  }
};
