# Third-party notices

The package source is Apache-2.0 except for the components below, which keep
their upstream licenses.

| Path | Origin | License |
| --- | --- | --- |
| `assets/web/ii_ffmpeg_universal_worker.js` | Adapted from `@ffmpeg/ffmpeg` 0.12.15 | MIT |
| `tool/patches/ffmpeg-5.1-web.patch` | Modified excerpt of FFmpeg n5.1.10 `fftools`, adapting ffmpeg.wasm `f876f907` | LGPL-2.1-or-later |
| `third_party/ffmpeg_kit_flutter_mobile_full/` | Modified `ffmpeg_kit_flutter_new_full` 2.4.1 Flutter plugin | LGPL-3.0 |

## @ffmpeg/ffmpeg worker

`assets/web/ii_ffmpeg_universal_worker.js` is adapted from
`@ffmpeg/ffmpeg` 0.12.15 `dist/esm/worker.js`. The exact upstream source used
for the adaptation has SHA-256
`feff0ac937ea225e997e1fae997a74f8b8d572423a526da59eb56624b1f3cde7`.

Copyright (c) 2019 Jerome Wu

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## FFmpeg web patch

`tool/patches/ffmpeg-5.1-web.patch` modifies `fftools/cmdutils.c`,
`fftools/ffmpeg.c`, and `fftools/ffprobe.c` from FFmpeg n5.1.10
(https://ffmpeg.org/releases/ffmpeg-5.1.10.tar.xz) so the command-line tools
run inside a WebAssembly worker: exits are reported to JavaScript instead of
terminating the module, and progress is forwarded to the bridge. The changes
adapt the Emscripten modifications that ffmpeg.wasm carries in `src/fftools`
at commit `f876f907c7e9b9bf51d4ed0b913a855a63ae63fc`
(https://github.com/ffmpegwasm/ffmpeg.wasm).

Copyright (c) 2000-2003 Fabrice Bellard (`cmdutils.c`, `ffmpeg.c`)
Copyright (c) 2007-2010 Stefano Sabatini (`ffprobe.c`)
and the other FFmpeg and ffmpeg.wasm contributors. Modified by Intelligent
Iterations.

The patch is distributed under the GNU Lesser General Public License, version
2.1 or (at your option) any later version, the license of the FFmpeg files it
modifies. The same notice heads the patch file. Engines built with it are
covered by the obligations in `native-engine-provenance.md`.

## FFmpegKit Flutter plugin

`third_party/ffmpeg_kit_flutter_mobile_full/` is a modified, mobile-only copy
of `ffmpeg_kit_flutter_new_full` 2.4.1
(https://github.com/sk3llo/ffmpeg_kit_flutter), itself derived from FFmpegKit
by Taner Sener (https://github.com/arthenica/ffmpeg-kit). It is distributed
under the GNU Lesser General Public License, version 3: the full text is in
that directory's `LICENSE`, with the GNU General Public License, version 3,
that it extends in `COPYING`. The modifications and their dates are listed in
that directory's `CHANGELOG.md` under `2.4.1+ii.1`. The directory contains no
native binaries.
