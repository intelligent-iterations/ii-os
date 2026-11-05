# Asset provenance

This inventory covers binary and brand assets included in the public release.
It is part of the release boundary and must be reviewed when an asset changes.

| Paths | Origin | Distribution terms |
| --- | --- | --- |
| `web/icons/`, `web/favicon*`, `web/apple-touch-icon.png`, Android launcher icons, `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | ii-os mark authored by Intelligent Iterations; raster variants are derived from the SVG mark described in `docs/ii-os-brand.md`, and the iOS app icons are rendered from `web/icons/ii-os-mark-maskable.svg` | Distributed under the repository license. The release owner confirmed on 2026-10-31 that Intelligent Iterations owns the mark and may publish it. |
| `ios/Runner/Assets.xcassets/LaunchImage.imageset/`; launcher icons, launch images, and web icons under `packages/*/example/` | Unmodified images from the Flutter SDK project templates (flutter_tools templates and `flutter_template_images` 5.0.0) | BSD-3-Clause, Copyright 2014 The Flutter Authors (https://github.com/flutter/flutter/blob/master/LICENSE). |
| `packages/ii_ffmpeg_universal/example/android/gradle/wrapper/gradle-wrapper.jar` | Gradle 2.10 wrapper from the Flutter Android template; SHA-256 `16caeaf66d57a0d1d2087fef6a97efa62de8da69afa5b908f40db35afc4342da` matches the [official wrapper checksum](https://services.gradle.org/distributions/gradle-2.10-wrapper.jar.sha256) | Apache-2.0, Gradle Inc. The license text is in the repository `LICENSE`; the upstream distribution notice and its source are preserved in the adjacent `NOTICE`. The JAR does not embed a license file. |
| `test/goldens/` | Deterministic screenshots rendered from repository-owned test fixtures and ii-os UI source | Distributed under the repository license. They do not contain customer media. |
| `test/fixtures/video_editor/media/linked-offset-v1/linked-offset.mov` | Generated entirely from FFmpeg color and sine filters | The exact command, tool version, hashes, and claims are recorded beside the fixture in `provenance.json`. No external media was used. |
| `packages/ii_os_design_system/fonts/Manrope-*.ttf` | Static Latin subsets generated from the Manrope variable font | SIL Open Font License 1.1. Upstream hash, generation recipe, copyright notice, and full license are in the same `fonts/` directory. |
| `packages/ii_flutter_video_editor/test/fixtures/linked-offset-v1/linked-offset.mov` | Generated test fixture with its exact command, hashes, and claims in the adjacent `provenance.json` | Distributed as test data under the repository license; no external media was used. |
| `packages/ii_ffmpeg_universal/assets/web/ii_ffmpeg_universal_worker.js` | Adapted from `@ffmpeg/ffmpeg` 0.12.15 | MIT; upstream copyright, hash, and notice are preserved in `packages/ii_ffmpeg_universal/docs/third-party-notices.md`. |
| `packages/ii_ffmpeg_universal/third_party/ffmpeg_kit_flutter_mobile_full/` | Modified FFmpegKit Flutter plugin source (no binaries); modifications are dated in its `CHANGELOG.md` | LGPL-3.0 in its `LICENSE`, with the GPL-3.0 text it extends in `COPYING`. |
| `packages/ii_ffmpeg_universal/tool/patches/ffmpeg-5.1-web.patch` | Modified excerpt of FFmpeg n5.1.10 `fftools` sources, adapting the ffmpeg.wasm changes at commit `f876f907` | LGPL-2.1-or-later; origin, copyright holders, and license are in the patch header and `packages/ii_ffmpeg_universal/docs/third-party-notices.md`. |

Implementation-owned downloads under `web/downloads/` are deliberately not
exported. A deployment may expose a separately reviewed helper through the
explicit configuration contract documented in `docs/deployment.md`.
