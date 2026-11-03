# Cross-platform FFmpeg ecosystem research

Research date: 2026-07-20.

The objective was not to invent a media engine. It was to select maintained
native and browser engines, put a small backend-neutral contract around them,
and preserve a package-owned replacement path for a fully controlled source
build without exposing engine selection to applications.

## Findings

| Candidate | Current useful surface | Decision |
| --- | --- | --- |
| Original [arthenica/ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit) | Historically broad Flutter/mobile support, but archived after retirement. | Do not take a new direct dependency. Keep compatibility with its successor API shape. |
| [FFmpegKitNext](https://github.com/arthenica/ffmpeg-kit-next) | Official, maintained continuation of FFmpegKit with modern FFmpeg and configurable LGPL/GPL builds. | Preferred long-term engine when this package owns reproducible native binary builds. Replace the package-owned mobile adapter after equivalent lifecycle proof. |
| [`ffmpeg_kit_flutter_new_full`](https://pub.dev/packages/ffmpeg_kit_flutter_new_full) | Maintained packaged Flutter fork spanning Android, iOS, macOS, and Windows; its `full` variant omits GPL-only libraries by default. | Vendor its small Dart/mobile bridge for Android and iOS only, pin and verify native artifacts, and exclude its Windows binary build path. Re-audit every upgrade. |
| [`ffmpeg_wasm`](https://pub.dev/packages/ffmpeg_wasm) Dart package | Wraps an older JavaScript API and uses legacy Dart web interop. | Rejected. Its wrapper layer would become the maintenance bottleneck. |
| [`@ffmpeg/ffmpeg`](https://github.com/ffmpegwasm/ffmpeg.wasm) | Active worker-based browser API, asynchronous virtual file system, single and multi-thread cores. | Use the current JavaScript API through a very small `dart:js_interop` bridge. Host engine assets with the app. |
| [`video_editor`](https://pub.dev/packages/video_editor) | Useful trim, crop, rotate, and preview primitives. | Inspiration only; it is not a multi-lane composition model or universal rendering layer. |
| [OpenTimelineIO](https://opentimelineio.readthedocs.io/en/latest/tutorials/otio-timeline-structure.html) | Mature non-destructive timeline vocabulary: tracks, clips, gaps, source ranges, and available ranges. | Adopt the conceptual distinction between timeline placement and source media ranges in the editor package. |
| [OpenCut](https://github.com/OpenCut-app/OpenCut) | Modern open editor with a plugin-oriented architecture across web/desktop/mobile ambitions. | Validate the controller/plugin direction, without copying its implementation or making the FFmpeg layer editor-aware. |
| [Remotion licensing](https://www.remotion.dev/docs/license) | Sophisticated programmatic video system with use-dependent commercial terms. | Architecture inspiration only; no dependency and no copied code. |

## Browser constraints

The upstream [usage documentation](https://ffmpegwasm.netlify.app/docs/getting-started/usage/)
shows a worker-based loader and separate core assets. The wrapper therefore:

- loads `@ffmpeg/ffmpeg` and the core from application-hosted same-origin URLs,
  requiring SHA-256 for every evaluated byte, with no public URL/origin
  override;
- defaults to the single-thread core, avoiding mandatory COOP/COEP headers;
- transfers only a private copy of each input byte array;
- exposes cancellation, logs, progress, output bounds, and a deterministic
  disposal boundary;
- requires explicit safe demuxers, injects nested-protocol and `-fs` constraints,
  uses a package-owned class worker to reject MEMFS writes before a hard
  workspace quota and to expose output sizes for per-output rejection before
  copying, and requires meaningful bounded JSON for FFprobe;
- does not bundle the large core inside this Dart package.

The package uses Flutter's current
[Wasm-compatible JavaScript interop](https://docs.flutter.dev/platform-integration/web/wasm#using-compatible-js-interop-libraries):
`dart:js_interop` and `package:web`, never `dart:html`, `dart:js`, or
`package:js`. Both JavaScript and `--wasm` production builds are exercised
because Flutter documents a JavaScript fallback when WasmGC is unavailable.

The locked browser build applies a reviewed patch to the exact FFmpeg 5.1.10
source and ffmpeg.wasm binding. It makes the command entry points reusable,
preserves the native FFprobe return value, exports cancellation, and removes
pthread worker lookup. The package-owned worker accepts the core only when its
heap, FFprobe, and loader functions match the reviewed source shape. Browser
tests prove native `0` for a valid probe and nonzero for invalid input; no
stdout/JSON heuristic changes engine success.

The browser engine is substantially slower than native FFmpeg and consumes
memory proportional to input, working state, and output. The worker-enforced
MEMFS quota bounds virtual file bytes, but Wasm does not expose a portable
per-job total heap/RSS quota to this wrapper. Dart also documents that converting
a Dart-created
[`Uint8List` to `JSUint8Array`](https://api.flutter.dev/flutter/dart-js_interop/Uint8ListToJSUint8Array/toJS.html)
may clone the bytes under the Wasm compiler. The package therefore keeps hard
browser input, output, and workspace ceilings below the configurable native
limits. The editor must use it for bounded interactive exports; a hostile-input
service still needs process-level isolation rather than treating a phone
browser as a render farm.

The repo recipe builds a non-GPL, network-disabled core instead of downloading
the upstream GPL binary. Each shipping application must still retain the exact
attestation, corresponding sources, and notices and confirm that enabled codecs
and linkage match its distribution obligations.

## Native constraints

Native execution has two strategies behind one contract:

1. A reviewed, mobile-only FFmpegKit adapter runs in-process on Android/iOS and
   surfaces job-scoped cancellation and FFprobe. To avoid FFmpegKit's retained
   per-session histories, the universal adapter disables native redirection and
   statistics delivery, suppresses CLI statistics, caps history at 32
   metadata-only records, maps completion and return-code snapshots directly
   from native events, serializes package sessions, admits only one Flutter
   engine per process, and uses indeterminate progress at this layer. A release
   pipeline should build its Android AAR and iOS XCFramework archives from exact
   commits and pass their attestations directly into the application build.
2. Direct process execution supports Linux, macOS, Windows, and controlled
   server environments. It passes an argument vector directly, never starts a
   shell, and uses an owned per-job directory. Managed native work sets a
   libavutil per-block allocation ceiling, reserves one such block of output
   headroom per declared muxer, and monitors directory growth. Those are
   defense-in-depth controls, not an OS filesystem or RSS quota. The release
   builder owns recursive loader auditing and Mach-O localization; applications
   bundle the resulting hash-attested closure, so runtime execution needs no
   platform inspection or mutation tools.

The mobile adapter is a bridge, not an excuse to freeze engine maintenance.
The current release recipe builds its FFmpegKit-compatible engine from exact
sources and emits provenance and license manifests. A future move to
FFmpegKitNext can replace that package-owned engine only after equivalent
lifecycle and live-platform proof.

FFmpeg's official
[`protocol_whitelist` contract](https://ffmpeg.org/ffmpeg-protocols.html#Protocol-Options)
states that protocols are otherwise allowed by default and that nested opens
have their own subsets. Managed jobs therefore insert `-protocol_whitelist
file` for every input. The caller must name an allowlisted demuxer and reference
only a declared package-owned resource (or an allowlisted generated `lavfi`
source); desktop child stdin is closed. Network, standard-stream, playlist, and
side-file access remain outside the managed profile. The safe demuxer list
excludes concat, HLS, DASH, SDP, and other manifest formats. FFmpeg's official
[MOV demuxer documentation](https://ffmpeg.org/ffmpeg-formats.html#mov_002fmp4_002f3gp)
also identifies `enable_drefs` and `use_absolute_path` as the switches that load
external tracks, disables both by default, and calls the latter a security
risk; neither option exists in the managed argument profile.

## Boundary decision

This package owns execution mechanics only: engine loading, named resources,
process isolation, limits, progress, cancellation, and results. Timeline
semantics, text overlays, codec presets, editing UI, uploads, and workspace
authorization belong to the editor or consuming application. That separation
keeps the FFmpeg foundation reusable and prevents a media engine wrapper from
becoming a product-specific control plane.
