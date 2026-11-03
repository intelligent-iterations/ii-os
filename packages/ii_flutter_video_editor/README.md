# ii_flutter_video_editor

A controlled Apache-2.0 Flutter video-editor package for web, Android, iOS,
macOS, and Linux. It provides immutable multi-lane timeline state, exact cut
operations, resizable still-image and caption overlays, callback-customizable
UI, and a safe adapter to `ii_ffmpeg_universal`.

The package is developed inside the ii-os monorepo and is not published to
pub.dev. It owns no deployment identity or durable application state.

The supported floor is Dart 3.12.1 and Flutter 3.44.1, matching the universal
runtime dependency.

The package deliberately does not fetch assets, own playback, persist projects,
upload bytes, or choose cloud credentials. The consuming app owns those
concerns and supplies preview, state, render, and persistence callbacks.

On macOS, the Universal FFmpeg desktop backend launches an attested `ffmpeg`
child process. The example therefore runs without App Sandbox entitlements.
Mac App Store consumers must move that execution into a separately signed,
appropriately entitled helper or choose another compliant native integration;
enabling App Sandbox on the example while retaining direct process execution is
not supported.

```dart
IiFlutterVideoEditor(
  project: project,
  playhead: playhead,
  selection: selection,
  onProjectChanged: (next) => setState(() => project = next),
  onPlayheadChanged: (next) => setState(() => playhead = next),
  onSelectionChanged: (next) => setState(() => selection = next),
  onAddCaptionRequested: () => openCaptionFormAt(playhead),
  onAddImageOverlayRequested: () => importImageAt(playhead),
  onRenderRequested: () => render(project),
  previewBuilder: (context, project, position, selection) {
    return MyControlledPreview(project: project, position: position);
  },
)
```

Selected timeline clips can be removed with Delete or Backspace on a hardware
keyboard, the toolbar remove button, or the action sheet opened by a long press
or right click. Ctrl/Command+Z and the toolbar undo control restore up to 50
local editor commands. A consuming app that already owns command history can
instead supply `canUndo` and `onUndoRequested`; durable project state and
persistence history always remain application-owned.

Image importing remains an application-owned byte-selection boundary. After
the app supplies a bounded PNG, JPG, JPEG, or WebP `MediaSource`, it can create
a top-most lane with `addEditorImageOverlay`. Selecting that image exposes
touch-sized move and resize handles over the preview:

```dart
project = addEditorImageOverlay(
  project: project,
  laneId: 'brand-overlay',
  clipId: 'brand-image',
  source: importedImage,
  timelineStart: playhead,
  duration: MediaTime.seconds(4),
);
```

Each default lane header also has a compact menu for locking, visibility or
audio muting, and bottom-to-top layer ordering.

When one imported source contains video and audio whose decoded streams begin
at different timestamps, describe each stream with its own
`EditorNewLanePlacement`. `timelineOffset` is measured from the requested
placement point, while `sourceRange.start` is measured from that stream's first
decoded frame or sample. The linked clips can then move and split as one editing
unit without compilation pulling the later stream forward.

Caption text is drawn by Flutter into a bounded transparent PNG and then
supplied to Universal FFmpeg as an image layer. Caller text and font paths
never become FFmpeg filter expressions.

Create an `EditorRenderCancellationToken` before calling
`EditorCompositionCompiler.compile`. Custom raster callbacks and source streams
receive or observe bounded preparation. The returned `EditorRenderPlan` contains
the validated Universal FFmpeg job and output metadata; the consuming app owns
engine scheduling, execution cancellation, and the bounded result bytes.

Call `preflightEditorRender` before accepting an edit, saving, or starting a
render. It returns a typed `EditorRenderFeasibility` and exact accounting for
the current occurrence-layer compiler without reading source streams or
rasterizing captions. `MediaLimits.maxEstimatedOutputBytes` can reserve
container/muxing headroom below the hard `maxOutputBytes` result cap.
`MediaLimits.maxDeclaredMediaBytes` can keep imported media below the larger
aggregate `maxInputBytes` ceiling; preflight reserves the configured bounded
caption bytes in that remaining capacity:

```dart
final feasibility = preflightEditorRender(
  project,
  limits: editorLimits,
  mediaLimits: targetMediaLimits,
);
if (!feasibility.isStructurallyFeasible) {
  showTargetBlocker(feasibility.issues.first);
}
```

This result is deliberately structural, not a "render ready" promise. Media
availability, declared-length verification, caption PNG bytes and fit, decoder
support, engine startup, and execution remain preparation or runtime concerns.
Use `EditorCompositionCompiler.preflight` when the target also supplies a
Universal FFmpeg safety policy; it intersects the target byte ceilings before
reporting.

Production hosts can bind all three limit layers once and reuse the same
compiler for admission and lowering:

```dart
final target = EditorRenderTarget(
  editorLimits: hostEditorLimits,
  mediaLimits: hostMediaLimits,
  safety: hostFfmpegSafety,
);
final compiler = EditorCompositionCompiler.forTarget(target);
final feasibility = compiler.preflight(project);
```

See [`docs/architecture.md`](docs/architecture.md) for the data model,
integration boundary, and verification matrix.
