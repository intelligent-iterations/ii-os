import { constants, closeSync, fstatSync, lstatSync, openSync, readSync, readdirSync, readlinkSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, sep } from 'node:path';

const maximumBytes = 512 * 1048576, maximumEntries = 100000;
const hash = value => 'sha256:' + createHash('sha256').update(value).digest('hex');

/** Content identity includes paths, empty directories, executable bits and links. */
export function preparedTreeManifest(directory) {
  const root = resolve(directory), stat = lstatSync(root);
  if (!stat.isDirectory() || stat.isSymbolicLink() || realpathSync(root) !== root || stat.uid !== process.getuid()) throw Error('unsafe-prepared-source');
  const entries = []; let bytes = 0;
  function visit(path, relative) {
    for (const raw of readdirSync(path, { encoding: 'buffer' }).sort(Buffer.compare)) {
      const name = raw.toString('utf8');
      if (!Buffer.from(name).equals(raw)) throw Error('invalid-prepared-path');
      const file = join(path, name), key = relative ? relative + '/' + name : name;
      if (entries.length >= maximumEntries) throw Error('prepared-source-entry-limit');
      const item = lstatSync(file);
      if (item.isDirectory()) { entries.push([key, 'directory']); visit(file, key); }
      else if (item.isSymbolicLink()) {
        const target = readlinkSync(file);
        const destination = resolve(dirname(file), target);
        if (target.startsWith('/') || (destination !== root && !destination.startsWith(root + sep))) throw Error('prepared-source-link-escape');
        entries.push([key, 'link', target]);
      } else if (item.isFile() && item.nlink === 1) {
        bytes += item.size;
        if (bytes > maximumBytes) throw Error('prepared-source-byte-limit');
        const fd = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
        try {
          const before = fstatSync(fd);
          if (before.dev !== item.dev || before.ino !== item.ino || before.size !== item.size) throw Error('prepared-source-changed');
          const digest = createHash('sha256'), buffer = Buffer.alloc(1048576);
          let consumed = 0, count;
          while ((count = readSync(fd, buffer)) > 0) {
            consumed += count;
            if (consumed > item.size) throw Error('prepared-source-changed');
            digest.update(buffer.subarray(0, count));
          }
          const after = fstatSync(fd);
          if (consumed !== item.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) throw Error('prepared-source-changed');
          entries.push([key, 'file', Boolean(item.mode & 0o111), 'sha256:' + digest.digest('hex')]);
        } finally { closeSync(fd); }
      } else throw Error('unsupported-prepared-entry');
    }
  }
  visit(root, '');
  const canonical = JSON.stringify({ schemaVersion: 1, entries });
  return { canonical, digest: hash(canonical), bytes: Buffer.byteLength(canonical) };
}

// Executed before setup or the agent. The script is fixed trusted adapter code;
// paths are argv values, never interpolated source or shell commands.
const verifyProgram = `import hashlib,json,os,stat,sys
root=os.path.realpath(sys.argv[1]); entries=[]; total=0
def visit(path,relative):
 global total
 for name in sorted(os.listdir(path),key=lambda x:x.encode('utf-8')):
  name.encode('utf-8',errors='strict')
  file=os.path.join(path,name); key=relative+'/'+name if relative else name
  if len(entries)>=100000: raise ValueError('entry-limit')
  item=os.lstat(file)
  if stat.S_ISDIR(item.st_mode): entries.append([key,'directory']); visit(file,key)
  elif stat.S_ISLNK(item.st_mode):
   target=os.readlink(file); destination=os.path.abspath(os.path.join(path,target))
   if os.path.isabs(target) or (destination!=root and not destination.startswith(root+'/')): raise ValueError('link-escape')
   entries.append([key,'link',target])
  elif stat.S_ISREG(item.st_mode) and item.st_nlink==1:
   total+=item.st_size
   if total>536870912: raise ValueError('byte-limit')
   fd=os.open(file,os.O_RDONLY|os.O_NOFOLLOW)
   with os.fdopen(fd,'rb') as stream:
    before=os.fstat(stream.fileno()); digest=hashlib.sha256(); consumed=0
    while True:
     chunk=stream.read(1048576)
     if not chunk: break
     consumed+=len(chunk)
     if consumed>item.st_size: raise ValueError('changed')
     digest.update(chunk)
    after=os.fstat(stream.fileno())
    if consumed!=item.st_size: raise ValueError('changed')
   if (before.st_dev,before.st_ino,before.st_size)!=(item.st_dev,item.st_ino,item.st_size) or before.st_mtime_ns!=after.st_mtime_ns or before.st_ctime_ns!=after.st_ctime_ns: raise ValueError('changed')
   entries.append([key,'file',bool(item.st_mode&0o111),'sha256:'+digest.hexdigest()])
  else: raise ValueError('entry-type')
visit(root,'')
data=json.dumps({'schemaVersion':1,'entries':entries},ensure_ascii=False,separators=(',',':')).encode('utf-8')
print(json.dumps({'digest':'sha256:'+hashlib.sha256(data).hexdigest(),'bytes':len(data)}))
`;

export function createPreparedSourceVerifier() {
  function expected(record) {
    const value = record.inputs.artifacts.find(item => item.role === 'prepared-tree')?.artifact;
    if (!value) throw Error('prepared-source-identity-missing');
    return value;
  }
  function compare(actual, wanted) {
    if (actual.digest !== wanted.digest || actual.bytes !== wanted.bytes) throw Error('prepared-source-identity-mismatch');
  }
  return {
    async verifyLocal({ directory, record }) { compare(preparedTreeManifest(directory), expected(record)); },
    async verifyWorker({ worker, record, deadlineMs, signal }) {
      const output = await worker.run({ command: '/usr/bin/python3', args: ['-c', verifyProgram, worker.workspace + '/repository'],
        timeoutMs: Math.min(30000, deadlineMs - Date.now()), maxOutputBytes: 4096, signal });
      compare(JSON.parse(output), expected(record));
    },
  };
}
