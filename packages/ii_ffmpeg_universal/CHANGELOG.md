## 0.0.1

* Add a backend-neutral, structured FFmpeg/FFprobe execution API.
* Support Android and iOS through a checksummed mobile FFmpegKit adapter.
* Support Linux and macOS through shell-free process execution; Windows fails
  closed until a live isolated runtime proof exists.
* Support browser rendering through same-origin ffmpeg.wasm assets.
* Enforce managed arguments, resource ceilings, cancellation, timeouts, and
  owned-workspace cleanup.
* Normalize cancellation and timeout outcomes across backends and harden
  Android/iOS Flutter-engine detach behavior.
* Reject side-effecting positional filter options and cap aggregate argv size.
* Make persistent publication win racing cancellation after atomic commit.
* Enforce one FFmpegKit-owning Flutter engine per process and reconstruct
  completion without relying on bounded native history.
* Enforce browser workspace quotas at low-level MEMFS write, allocate,
  truncate, ftruncate, and msync paths.
* Fail closed on missing/substituted Android native artifacts and compare iOS
  caches with freshly downloaded checksummed archives.
