## 0.1.0

- Preserve decoded video/audio synchronization during new-lane placement with
  independent source ranges, available durations, and timeline offsets on one
  edit-linked source occurrence, including leading-silence materialization
  that survives FFmpeg audio mixing and stream-local timestamp normalization
  before trims or splits.
- Reject span and split edits that would change a locked linked unit, preserve
  untouched locked lanes by identity, and keep collision-safe linked tail
  partitions together after ripple removal.
- Add pure, typed render-feasibility preflight with exact current layer, input,
  declared-byte, estimated-output-byte, caption-pixel, source-use, and
  output-profile accounting.
- Let render targets reserve encoded-output headroom with
  `MediaLimits.maxEstimatedOutputBytes`, while retaining the separate hard
  `maxOutputBytes` execution cap.
- Separate a target's declared-media allowance from its aggregate prepared
  input ceiling, and reserve bounded caption bytes during pure preflight so a
  structurally admitted project cannot fail only after caption rasterization.
- Add immutable `EditorRenderTarget` profiles that intersect editor, media,
  per-output, total-output, and workspace safety limits once for preflight and
  compilation.
- Run the compiler from the same preflight layer plan and reject structural
  blockers before any source read or caption rasterization.
- Generate collision-free bounded caption source IDs while retaining the
  compiler's distinct-source identity defense.
- Add Delete/Backspace, toolbar, long-press, and right-click clip removal with
  bounded local undo and non-throwing validation rollback.
- Add compact lane lock, visibility, mute, and layer-order controls.
- Add still-image overlay construction plus on-preview move and resize handles.
- Add the controlled multi-lane editor, exact split operations, bounded caption
  rasterization, and compilation into validated Universal FFmpeg plans.
- Keep engine scheduling, execution, cancellation, uploads, and persistence in
  the consuming application.
