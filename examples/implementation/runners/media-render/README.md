# media-render runner

Finishes a video-editor export on a CPU runner. The dashboard's editor has
already compiled the timeline into one FFmpeg invocation (`render_manifest`);
this runner stages the files that invocation names and runs ii-os's own
`tool/render_editor_manifest.dart`, the same renderer and FFmpeg safety
allowlist the browser uses.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `editor-render` | `video-editor-render` | `.github/workflows/video-editor-render.yml` |

## Hardware

Any x86-64 Linux runner with Docker: 4 CPU cores, 8 GB of RAM and about
20 GB of free disk is comfortable. No GPU and no model folder.

## Build the image

The image carries an ii-os source tree, so build it from the ii-os commit
your dashboard is deployed from; a render compiled by one ii-os version is
rendered by that version's renderer.

```bash
git clone https://github.com/intelligent-iterations/ii-os /path/to/ii-os-checkout
git -C /path/to/ii-os-checkout checkout <the commit your dashboard runs>
docker build -f runners/media-render/Dockerfile \
  --build-context ii-os=/path/to/ii-os-checkout \
  -t registry.example.com/ii-os/media-render:2026-11 .
docker push registry.example.com/ii-os/media-render:2026-11
```

Set `II_OS_RUNNER_IMAGE_MEDIA_RENDER` to the pushed image pinned by digest.
Flutter is pinned to the commit ii-os builds with; `flutter pub get
--enforce-lockfile` resolves ii-os's locked packages at build time, so the
container needs no network when it renders.

## What runs

- The claim stages up to 12 source files (image, video or audio) in ordinal
  order. The task refuses a render whose manifest names a different asset, a
  different size, or a different order than what was staged.
- Only `video/mp4` and `video/webm` exports are produced, the types ii-os
  stores as workflow artifacts, up to the manifest's own `maxOutputBytes`
  (at most 512 MiB).
- The render has a 40-minute ceiling inside a 90-minute job.
