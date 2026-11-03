# ii_ffmpeg_universal

Backend-neutral FFmpeg execution for Flutter applications. One structured Dart
API runs media jobs on Android, iOS, Linux, macOS, and browsers without shell
command construction in application code.

This Apache-2.0 package is developed in the ii-os monorepo and is not published
to pub.dev. The vendored mobile adapter and generated engine distributions keep
their own licenses and notices; see `docs/third-party-notices.md` and
`docs/native-engine-provenance.md`.

## Backends

| Platform | Default engine | Input forms | Notes |
| --- | --- | --- | --- |
| Android, iOS | Vendored mobile FFmpegKit adapter | bytes, local paths | In-process FFmpegKit; non-development builds require locally attested engines built from exact source commits. |
| Linux, macOS | verified `ffmpeg` / `ffprobe` process | bytes, local paths | Requires absolute application-bundled paths and SHA-256 values; never searches PATH or invokes a shell. The macOS process backend is incompatible with App Sandbox. |
| Windows | disabled | none | Fails with `unsupportedPlatform` until a live isolated Windows release proof exists. |
| Web | `@ffmpeg/ffmpeg` + ffmpeg.wasm | bytes | Runs locally in a browser worker with same-origin, SHA-256-verified application assets. |

Backend selection and worker code are package-owned. Applications select their
reviewed desktop and browser engine binaries through exact digest-bearing
bundle records. The root library exposes no backend injection surface; Dart's
`src/` privacy is a package convention rather than a runtime security boundary.
Production applications must import only `ii_ffmpeg_universal.dart`. They
cannot configure a shell, native adapter, class worker, or cross-origin engine
URL through the supported API.

The current macOS backend starts the exact attested executables as child
processes and therefore requires an unsandboxed host application. A sandboxed
Mac App Store application must put execution behind a separately designed,
signed, and reviewed helper boundary; enabling the process backend inside App
Sandbox is not a supported deployment model.

The iOS adapter is CocoaPods-only. Its pod prepare hook consumes the locally
attested source build; Flutter Swift Package Manager is intentionally not a
supported integration path because it cannot enforce that release artifact.
Android and iOS fail closed when a local attested engine is absent. The older
checksum-pinned binaries can be selected only for non-release development by
setting `II_FFMPEG_ALLOW_DEBUG_FALLBACK=true`; release tasks reject that mode.

## Usage

```dart
final ffmpeg = UniversalFfmpeg(
  configuration: FfmpegConfiguration(
    // Required only on desktop. The manifest and its files are app assets.
    desktopBundle: isDesktop
        ? await loadAttestedFfmpegDesktopBundle(
            rootPath: packagedEngineRoot,
            manifestSha256: packagedManifestSha256,
          )
        : null,
  ),
);
final result = await ffmpeg.execute(
  FfmpegJob(
    id: 'thumbnail',
    arguments: const [
      '-f', 'mov',
      '-i', 'source.mp4',
      '-frames:v', '1',
      '-f', 'image2',
      'thumbnail.png',
    ],
    inputs: [FfmpegBytesInput('source.mp4', sourceBytes)],
    outputs: const [FfmpegOutput('thumbnail.png')],
  ),
  onProgress: (progress) => updateProgress(progress.fraction),
);

final thumbnail = result.outputBytes['thumbnail.png'];
await ffmpeg.dispose();
```

Arguments refer to input and output resources by portable base name. On native
platforms the package materializes those names inside an owned disposable
workspace. In a browser it writes them to ffmpeg.wasm's in-memory file system.
The package copies browser inputs before crossing the JavaScript boundary so
the upstream transferable optimization cannot detach caller-owned byte arrays.
Every managed file input and FFmpeg output must have an explicit allowlisted
`-f` format. Auto-probed playlist/SDP inputs and extension-inferred muxers are
rejected, so media contents or a renamed manifest cannot silently select a
network-reading demuxer or side-file-producing format.

`FfmpegPathInput` and `FfmpegOutput.destinationPath` are native-only conveniences.
A destination is never overwritten unless `overwriteOutput` is explicitly true.

## Browser setup

Build the locked single-thread engine from exact source archives and commits,
then copy only its attested artifacts into the ignored example fixture:

```sh
python3 tool/build_web_engine.py --workspace /absolute/new/ii-web-engine
export II_FFMPEG_WEB_ENGINE_ATTESTATION=/absolute/new/ii-web-engine/artifacts/build-attestation.json
./tool/fetch_web_test_assets.sh
```

For an application, self-host reviewed engine files on the app's own origin and
provide their exact SHA-256 values with `FfmpegWebBundle`. The package verifies
every byte before evaluation. It evaluates the verified scripts from ephemeral
blob URLs, applies its reviewed FFprobe and Wasm-heap hooks only when the
expected upstream source shapes match exactly, and runs quota checks against
the selected core's real MEMFS before initialization succeeds. The browser
bridge and class worker are Flutter package assets and cannot be replaced
through configuration. The single-threaded core does not require cross-origin
isolation; enable it on a test server only so Flutter's separate Dart-Wasm path
really runs instead of its JavaScript fallback.

Because verification happens before evaluation, the reviewed scripts execute
from ephemeral blob URLs. A deployed application therefore needs this minimum
browser policy in addition to its own narrower `connect-src`, `img-src`, and
other directives:

```text
script-src 'self' blob: 'wasm-unsafe-eval'; worker-src 'self' blob:
```

Any harness you use to exercise a production web build should serve that
policy and run Chrome with its sandbox enabled rather than with `--no-sandbox`.

```dart
const webBundle = FfmpegWebBundle(
  ffmpegScriptUrl: 'ffmpeg/ffmpeg.js',
  ffmpegScriptSha256: '<64 hex characters>',
  coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
  coreScriptSha256: '<64 hex characters>',
  coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
  coreWasmSha256: '<64 hex characters>',
);
```

The locked recipe builds FFmpeg 5.1.10 without network, GPL, nonfree, TLS,
x264, or x265 support. It enables the reviewed libvpx, Opus, libass, FreeType,
FriBidi, HarfBuzz, and zlib surface and emits a source ledger, third-party
notices, verification result, and build attestation. Shipping applications must
still review the exact enabled codecs, linkage, corresponding-source delivery,
and notices for their own distribution.

Core script and Wasm responses are read as bounded streams. A declared length
over the ceiling is rejected before reading, and a chunk that would cross the
ceiling cancels the response reader before the bytes are assembled or hashed.

## Safety contract

- Jobs use `List<String>` arguments and no backend concatenates a shell command.
- Resource names are portable base names; traversal, separators, and duplicates
  are rejected.
- Managed inputs require an explicit safe demuxer. Direct protocol arguments
  are rejected by default and the engine receives a nested-protocol allowlist,
  preventing an auto-probed playlist/SDP payload from opening a remote URL.
- Per-resource and aggregate accepted input/delivered output size, workspace
  budget, individual and aggregate argv size, log size, timeout, cancellation,
  and overwrite behavior are governed by `FfmpegSafetyPolicy`.
- Path inputs are copied from one non-link descriptor/handle into the owned
  workspace before execution, so a path replacement cannot switch the bytes
  after validation. UNC/device/alternate-stream paths are rejected. The managed
  argument profile allows only reviewed filters and demuxers, rejecting filter
  file options, filters such as `drawtext`/`loudnorm` with positional file
  options, and muxers that can create undeclared side files. Binary stdout
  sinks are rejected; `-` is available only with the null muxer.
- No-overwrite destination installation is atomic, including when another
  process creates the destination while a job is running.
- Cancellation is best effort at the persistent publication boundary. If a
  destination is atomically installed while cancellation races the commit, the
  job reports success so callers never retry after an unreported side effect.
  Post-commit cleanup failure likewise cannot turn that durable mutation into
  a retryable failure; recoverable owned remnants are retained for inspection.
- Temporary native workspaces carry a structured ownership marker and an active
  OS file lock. Normal cleanup revalidates the exact per-run token. A workspace
  whose engine never confirms termination is preserved for operator inspection;
  the package never treats forgeable marker contents in a shared system temp
  directory as authority to delete state from an earlier process.
  A dedicated owned root records its own token; bounded startup recovery takes
  each abandoned workspace lock non-blockingly and deletes only an exact stale
  child whose owner, root token, marker, age, and dead creator identity still
  match. Destination copies are preceded by a flushed journal in that private
  workspace. Recovery removes only the journal's exact regular random-token
  partial sibling; a missing, linked, malformed, oversized, or unjournaled path
  is preserved. Active, malformed, oversized, or racing workspace state is
  preserved. Desktop callers must supply this root; mobile defaults it inside
  the app sandbox.
- `tool/build_desktop_engine.py` builds the reviewed network-disabled FFmpeg
  source lock, resolves its complete non-system closure, rewrites Mach-O load
  commands to staged `@loader_path` targets, audits Mach-O/ELF linkage, and
  emits a manifest, source ledger, notices, archive, and attestation. At
  runtime the app-bundled manifest loader accepts only regular files with the
  exact manifest and closure hashes. Initialization copies that closure into
  one owned engine directory, rehashes it, and seals modes through libc; it
  does not depend on `otool`, `readelf`, `install_name_tool`, `codesign`, PATH,
  or a shell. Each media job keeps a separate workspace.
- Browser engine URLs are same-origin by default. The packaged class worker
  rejects MEMFS writes before its hard workspace quota (at most 192 MiB) and
  exposes file sizes so every declared output is rejected against its effective
  limit before a read/copy (with an independent 64 MiB worker ceiling). Browser
  inputs are capped at 128 MiB.
- Managed native and browser renders receive an FFmpeg `-fs` ceiling derived
  from aggregate workspace/output budgets. Native execution additionally sets
  FFmpeg's per-block `-max_alloc`, reserves that much muxer headroom per output,
  and samples the owned workspace every 50 ms. This reduces overshoot but is not
  a filesystem quota. Managed browser probes are capped at 8 MiB, require
  exactly one input/output, and allow only reviewed metadata enumeration;
  packet and frame enumeration is rejected before execution. The browser
  backend accepts only FFprobe's upstream numeric success code.
- The in-process mobile adapter disables FFmpegKit log redirection, suppresses
  CLI statistics, throttles job-scoped progress delivery to four updates per
  second, caps native session history at 32 records, reconstructs completion
  and its return code directly from the immutable native event, serializes
  universal sessions across package instances in the application isolate, and
  admits only one Flutter engine per process.
  Initialization and launch are raced against cancellation and the job
  deadline, and byte/file copies check cancellation between bounded chunks.
  If engine detach or a late native launch prevents completion proof, the call
  fails within the termination grace period and preserves the locked workspace
  for operator inspection.
- Invalid jobs and policy failures throw a stable `FfmpegException` before an
  engine starts. Explicit cancellation and deadline expiry return a result;
  `cancelled` and `timedOut` are mutually exclusive on every backend.

These controls bound accepted transfers and delivered output. The browser
backend also bounds execution to the job deadline plus worker termination and
has a hard pre-write
MEMFS quota and a patched, initialization-verified ceiling on Wasm linear-memory
growth. Native backends expose
`capabilities.enforcesWorkspaceLimitBeforeWrite == false`: FFmpeg can finish a
muxer packet between enforcement points, and this wrapper cannot impose a
portable native filesystem quota. Native engines report
`enforcesEngineMemoryLimit == false`; `-max_alloc`, one codec/filter thread, and
the decoded-pixel ceiling are allocation-pressure guards, not total RSS/heap
limits. An in-process mobile engine may fail to acknowledge cancellation; in
that case the call fails after the termination join, the instance remains
poisoned/busy until native completion, and its workspace is preserved. Every
backend reports `acceptsUntrustedMedia == false`. This package's supported
native threat model is trusted workspace media. The wrapper rejects over-budget
results but does not make malformed media risk-free. Native apps that accept
hostile media need a separate OS sandbox/service with hard process, memory,
filesystem, descriptor, and wall-clock limits.

## Verification

```sh
flutter analyze
II_FFMPEG_ALLOW_AMBIENT_TEST_ENGINE=true flutter test
flutter test --platform chrome test/ii_ffmpeg_universal_test.dart

hashes="$(./tool/fetch_web_test_assets.sh)"
core_js="$(printf '%s' "$hashes" | jq -r .core_js_sha256)"
core_wasm="$(printf '%s' "$hashes" | jq -r .core_wasm_sha256)"
cd example
flutter build web --release --target lib/web_e2e_main.dart \
  --dart-define="II_FFMPEG_WEB_CORE_JS_SHA256=$core_js" \
  --dart-define="II_FFMPEG_WEB_CORE_WASM_SHA256=$core_wasm"
```

The ambient-engine opt-in is for deliberate local developer verification only;
it resolves, hashes, and tests the installed `ffmpeg` and `ffprobe`. Release CI
should instead supply an exact reviewed desktop bundle and manifest digest, so its
live proof cannot silently use `PATH`. The suite checks generated media,
cancellation, timeout, and cleanup.

The live desktop process test (`test/live_process_e2e_test.dart`) selects its
engine from these environment variables:

| Variable | Meaning |
| --- | --- |
| `II_FFMPEG_LIVE_TEST_ENGINE_ROOT` | Absolute path to an attested desktop bundle directory containing `manifest.json`. |
| `II_FFMPEG_LIVE_TEST_MANIFEST_SHA256` | Expected SHA-256 of that `manifest.json`; the bundle is loaded with `loadAttestedFfmpegDesktopBundle`. |
| `II_FFMPEG_ALLOW_AMBIENT_TEST_ENGINE` | Set to `true` to test the `ffmpeg` and `ffprobe` found on `PATH` instead. |

Set both `II_FFMPEG_LIVE_TEST_*` variables or neither: one without the other
fails the test rather than falling back. When both are set they take
precedence over the ambient opt-in. With none of the three set, the live test
fails and asks for an explicit engine.

The `lib/web_e2e_main.dart` target performs a real ffmpeg.wasm render and
probe, rejects an invalid probe, and verifies caller bytes remain intact. This
package does not ship a browser harness for it: serve `example/build/web` with
the browser policy above from your own static server, open it in a sandboxed
headless Chrome, and wait for the `data-ii-ffmpeg-e2e` attribute on `<body>`
to change from `running` to `pass:...` or `fail:...`. The `data-ii-dart-wasm`
attribute reports whether the Dart-Wasm path ran; check that it is `false` for
the JavaScript build and `true` for `flutter build web --wasm`, so a generated
JavaScript fallback cannot satisfy the Wasm lane.

An operator's release gate should bind the exact source commit, immutable
runtime identity, reviewed engine attestations, application manifests, retained
artifact hashes, and cleanup proof. Each application binding report should open
the APK/app/web/desktop package and compare embedded engine files with the
reviewed source-built engine. Compile-only artifacts must be labelled as such;
they are not runtime acceptance. Windows parser and staging work is retained
for future validation, but the runtime backend fails closed there until an
isolated live Windows proof passes.
Flutter's official workflow builds the runner with
[`flutter build windows`](https://docs.flutter.dev/platform-integration/windows/building),
while Microsoft documents that Windows containers do not support applications
that require a desktop. Neither a Linux container nor a compile-only check is
presented as a missing Windows runtime proof.

See [docs/ecosystem-research.md](docs/ecosystem-research.md) for the dated engine
and editor-architecture research behind these choices. Native artifact hashes,
provenance, and release obligations are recorded in
[docs/native-engine-provenance.md](docs/native-engine-provenance.md).
