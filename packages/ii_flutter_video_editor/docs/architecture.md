# ii_flutter_video_editor architecture

## Decision

`ii_flutter_video_editor` is the reusable editor
surface for ii-os web, mobile, and desktop. It is a controlled Flutter widget
and immutable edit model over `ii_ffmpeg_universal`; it is not a second media
runtime.

The package implements the first required editing slice:

- ordered multi-lane video, audio, and caption tracks;
- an exact split tool for video, audio, and caption clips;
- text superimposition through bounded Flutter-to-PNG rasterization;
- scrub, select, zoom, cut, add-caption, and render callbacks;
- lane-header, clip, preview, theme, caption-rasterizer, state, and persistence
  customization points;
- compilation of the editor-owned composition model into strict Universal
  FFmpeg jobs.

Dart 3.12.1 and Flutter 3.44.1 are the declared compatibility floor, matching
the universal runtime dependency used by every platform.

The parent app owns playback, asset selection, durable project records,
workspace authorization, render dispatch, upload, and failure UI. The editor
never fetches a URL, stores credentials, talks to GCS, or accepts FFmpeg command
text.

## Prior art applied

The model follows the useful separation in the mature Flutter
[`video_editor`](https://github.com/LeGoffMael/video_editor) package: editing
state is distinct from export execution and the host app controls the UI.
Unlike that package's primarily single-clip trim/crop surface, this package
uses explicit lanes and clips because ii-os needs multi-source composition.

Flutter's
[`CustomPainter`](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)
and
[`RepaintBoundary`](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)
contracts inform the timeline: the static ruler and each clip are isolated
from playhead movement, and `shouldRepaint` compares only ruler inputs.
Horizontal scrubbing uses Flutter's primary-button horizontal gesture contract.

No third-party editor runtime is embedded. That avoids adding native plugins,
remote export services, platform-specific project formats, or another FFmpeg
distribution.

## Data model

`EditorProject` owns fixed output dimensions, frame rate, duration, background,
output settings, and an ordered list of `EditorLane` values. Lane order is
render order from bottom to top. A lane has one closed kind:

- `video` accepts `EditorVideoClip`;
- `audio` accepts `EditorAudioClip`;
- `captions` accepts `EditorCaptionClip`.

Clips within a lane are ordered and non-overlapping. Separate lanes are how the
editor expresses concurrent video overlays, audio mixing, or simultaneous
captions. A PNG, JPG, JPEG, or WebP `EditorVideoClip` is a still-image visual;
`addEditorImageOverlay` places one in a new top-most lane and the same normalized
destination rectangle drives preview transforms and final composition. Every
time value is an integer-microsecond `MediaTime`.

The project is immutable. The package does not expose a mutable global
controller. `IiFlutterVideoEditor` receives the current project, playhead, and
selection and emits replacements through callbacks. It retains at most 50
prior immutable snapshots for session-local Ctrl/Command+Z and edit rollback;
durable persistence, collaboration, and ii-os state ownership remain outside
the package. A caller-provided undo callback replaces this local stack so two
histories never compete.

## Cut semantics

`splitEditorClip` accepts a project, exact selection, and absolute playhead. It
rejects missing or locked lanes and requires the playhead to be strictly inside
the clip.

For video and audio, the left clip keeps the original ID and source start. The
right clip receives a bounded deterministic ID and advances its source start by
the exact left duration. The two source ranges and two timeline ranges therefore
cover precisely the original range with no rounded frame or millisecond gap.
Caption splits duplicate text/style while partitioning display duration.

The transformed project is fully revalidated before it is returned.

## Linked source placement and synchronization

`addEditorSourceOnNewLanes` places one app-resolved byte source as a video
lane, an audio lane, or an edit-linked pair. Each `EditorNewLanePlacement`
retains an independent source range, available source duration, and nonnegative
timeline offset. The requested `timelineStart` is the pair's sync origin; a
clip begins at that origin plus its decoded stream offset.

The compiler first normalizes each decoded stream to its own zero, then trims
at that stream-local `sourceRange.start` and resets the trimmed timestamps.
This keeps ordinary trims and later split ranges independent of a container's
positive or negative presentation origin. Visual layers then receive their
absolute timeline timestamp. Audio layers receive equivalent bounded leading
silence before mixing, because FFmpeg's `amix` rebases timestamp-shifted inputs
and would otherwise pull a delayed stream back to zero. Keeping both values is
therefore necessary: the source range selects the intended stream-local
samples or frames, while the timeline offset preserves their relative
presentation time after the reset. Linked move and split operations retain
that relationship without treating source identity as edit group identity.
Stream probing, selection, and persistence remain host-owned.

## Caption safety boundary

Captions never become `drawtext` input. `FlutterCaptionRasterizer`:

1. derives exact destination pixels from the normalized output rectangle;
2. enforces pixel, character, line, font, padding, and output-byte limits;
3. uses Flutter `TextPainter` and a transparent canvas;
4. fails if text does not fit rather than silently clipping it;
5. enforces per-caption and aggregate pixel/PNG/input-byte ceilings;
6. encodes PNG bytes in compact `Uint8List` storage and disposes the Flutter
   text painter, image, and picture;
7. returns bytes to `EditorCompositionCompiler`, which creates a local
   `MediaSource` and a timed `MediaImageLayer`.

Apps that require a preloaded custom font may provide a
`CallbackCaptionRasterizer`. The callback receives the preparation token and
must stop promptly when it is cancelled. Its result is still bounded bytes; it
cannot inject paths, protocols, filter syntax, or credentials.

Caption preparation accepts an `EditorRenderCancellationToken`. Cancellation
is raced against every raster operation and checked inside the Flutter rasterizer.
Each raster also has an explicit
deadline; expiry cancels the cooperative token and returns a validation error
without waiting for a stalled callback. The compiler snapshots replayable
source streams under exact byte and time limits and bounds a non-cooperative
stream cancellation callback. The consuming app receives only a validated
`EditorRenderPlan` and owns Universal FFmpeg scheduling, execution, and
cancellation.

## Validation

`validateEditorProject` fails closed for:

- invalid or repeated project/lane/clip IDs;
- non-positive, odd, or out-of-range canvas/time values, with 4096-pixel and
  30-minute defaults plus non-configurable 8192-pixel/two-hour hard ceilings;
- lane/clip type mismatches;
- unsorted or overlapping clips in one lane;
- source/timeline duration disagreement;
- clips past project end;
- invalid normalized destinations, opacity, or volume;
- empty, oversized, or control-bearing captions;
- invalid font, padding, line, or raster bounds;
- configured lane/clip/caption ceilings.

`preflightEditorRender` is a separate, pure target-feasibility boundary. It
keeps ordinary validation broad enough to open and repair legacy projects while
reporting stable issue codes and the current compiler footprint: emitted
occurrence layers, identity-deduplicated media inputs, one prepared input per
caption, declared media bytes, worst-case bounded caption bytes,
bitrate-derived estimated output bytes, caption pixels, and peak visual/audio
concurrency. A target may set `MediaLimits.maxDeclaredMediaBytes` below the
aggregate input ceiling to reserve caption preparation capacity, and may set
`MediaLimits.maxEstimatedOutputBytes` below its hard output cap to reserve
container and muxing headroom. Hidden lanes and muted audio are excluded
exactly as they are by compilation. The compiler consumes the same ordered
layer plan and refuses structural blockers before caption rasterization or
source reads.

`EditorRenderTarget` is the immutable production composition root for these
limits. It intersects media limits with per-input, aggregate-input,
per-output, aggregate-output, and workspace engine policy once. A compiler
created with `EditorCompositionCompiler.forTarget` uses that same target for
both preflight and plan lowering; the legacy `limits:` constructor remains for
source compatibility and resolves to the default media and engine policy.

Preflight does not claim that sources are available, streams match declared
lengths, captions fit or produce bounded PNG bytes, codecs can decode, or a
backend can execute the job. Those remain preparation, decode, and runtime
states. Universal FFmpeg independently applies its managed input, argument,
byte, decode, output, workspace, and timeout ceilings before execution; the
editor's 24 emitted-layer and bitrate limits remain editor-owned policy.

## macOS execution boundary

The desktop Universal FFmpeg backend executes an attested, package-bound
`ffmpeg` child process. The example macOS application is intentionally not App
Sandbox-entitled because arbitrary packaged child-process execution is not a
valid sandbox design. A Mac App Store host must isolate execution in a
separately signed and appropriately entitled helper, or provide a different
compliant native backend. The editor package does not weaken or dynamically
rewrite the consuming application's entitlements.

## ii-os integration boundary

ii-os will:

1. authorize and fetch an asset reference from the selected workspace GCS
   bucket directly into browser/device-owned bytes;
2. wrap those bytes in replayable `MediaSource` callbacks;
3. own `EditorProject`, playhead, selection, preview player, and autosave;
4. show output-surface progress while captions compile and FFmpeg renders;
5. execute the validated plan through its owned Universal FFmpeg instance and
   upload the bounded output bytes directly to the workspace bucket with
   short-lived workspace-scoped authorization, then release the bytes;
6. persist only bounded edit metadata and the resulting opaque object reference;
7. dispose the engine after upload or cancellation.

No media bytes pass through ii-os Functions, Firestore, Firebase Storage, or a
bucket owned by the ii-os operator rather than the workspace.

## Verification matrix

| Contract | Proof |
|---|---|
| Model/lane validation | Pure Flutter tests for kinds, overlap, controls, bounds |
| Exact cut | Source/timeline coverage and locked/edge rejection tests |
| Controlled UI | Widget tests for delete, hold actions, undo, lane controls, image resize, scrub, cut, zoom, and narrow layout |
| Caption rasterization | Real Flutter engine PNG test and fit/pixel limits |
| Universal composition | Real rasterizer compilation with ordered layer assertions |
| Cancellation/deadline | Stalled callback tests that return on cancel and timeout |
| Native render | Real FFmpeg/FFprobe E2E that detects caption glyph pixels in decoded output |
| Web/mobile packages | Release web build and Android APK native-library inspection |
| Packaged native render | Android/iOS/macOS E2E decodes output through packaged FFmpeg and detects glyph pixels |
| Browser/Apple live execution | Operator-owned isolated runtime with exact locks, lifecycle evidence, and cleanup proof |

Compile-only platform results are not live proof. A release gate remains open
until a real isolated runtime executes the immutable client-media image and
records cleanup proof.
