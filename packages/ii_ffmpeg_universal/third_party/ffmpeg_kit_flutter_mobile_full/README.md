# Vendored FFmpegKit mobile adapter

This directory is a source-derived, mobile-only copy of
[`ffmpeg_kit_flutter_new_full` 2.4.1](https://pub.dev/packages/ffmpeg_kit_flutter_new_full/versions/2.4.1).
It exists solely as the Android/iOS implementation behind
`ii_ffmpeg_universal`; applications must use the structured universal API
instead of importing this package directly.

The upstream macOS and Windows plugin registrations and implementation wiring
are intentionally absent. Desktop execution belongs to the universal package's
direct-process adapter, while browsers use the packaged wasm bridge.

The ii-os modifications are recorded in `CHANGELOG.md`. Exact native artifact
origins, hashes, enabled libraries, licensing obligations, and update procedure
are documented in [`../../docs/native-engine-provenance.md`](../../docs/native-engine-provenance.md).
The derived adapter remains under its included LGPL license; native FFmpeg
distribution must separately satisfy the documented engine obligations.
