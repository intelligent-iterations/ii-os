# ii-ffmpeg-universal example

The macOS desktop-engine example intentionally runs without App Sandbox. The
current desktop backend spawns the exact attested FFmpeg executables bundled by
the host application; a sandboxed Mac App Store host must use a separately
designed and signed helper boundary instead of enabling this example backend.

Small application and live engine target for every generated Flutter platform.
The interactive screen renders an MP4 through the platform-selected backend.

Build the locked, network-disabled browser engine into a new absolute workspace,
then promote only its attested artifacts into the ignored test fixture:

```sh
python3 ../tool/build_web_engine.py --workspace /absolute/new/ii-web-engine
export II_FFMPEG_WEB_ENGINE_ATTESTATION=/absolute/new/ii-web-engine/artifacts/build-attestation.json
hashes="$(../tool/fetch_web_test_assets.sh)"
core_js="$(printf '%s' "$hashes" | jq -r .core_js_sha256)"
core_wasm="$(printf '%s' "$hashes" | jq -r .core_wasm_sha256)"
flutter build web --release --target lib/web_e2e_main.dart \
  --dart-define="II_FFMPEG_WEB_CORE_JS_SHA256=$core_js" \
  --dart-define="II_FFMPEG_WEB_CORE_WASM_SHA256=$core_wasm"
```

Serve `build/web` from your own static server with the browser policy in the
package README and open it in a sandboxed headless Chrome; a browser harness is
not included. The page sets `data-ii-ffmpeg-e2e` on `<body>` to `pass:...` or
`fail:...`, and `data-ii-dart-wasm` to whether the Dart-Wasm path ran. Repeat the
Flutter build with `--wasm` and confirm `data-ii-dart-wasm` is `true` to prove
the Dart-Wasm client. The source ledger, notices, verification result, and
engine hashes live beside the attestation.

For Linux or macOS, build the reviewed desktop closure into a new absolute
workspace, copy its `assets/` contents into `assets/desktop_engine/`, and bind
the emitted manifest hash into the release app:

```sh
python3 ../tool/build_desktop_engine.py --workspace /absolute/new/ii-desktop-engine
manifest_sha="$(jq -r .manifest_sha256 /absolute/new/ii-desktop-engine/build-attestation.json)"
flutter build macos --release \
  --dart-define="II_FFMPEG_DESKTOP_MANIFEST_SHA256=$manifest_sha"
```

Release automation should perform this promotion in disposable state, run the
packaged engine from the release app bundle, keep the engine evidence, and
remove only its own source staging files before checking that the source tree
is clean.
