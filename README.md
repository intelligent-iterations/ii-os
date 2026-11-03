# ii-os

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/intelligent-iterations/ii-os/badge)](https://scorecard.dev/viewer/?uri=github.com/intelligent-iterations/ii-os)

ii-os is a self-hostable Flutter operator console and Dart control plane for
multi-tenant workspaces, human-approved automation, media workflows, and
provider-backed infrastructure.

The public distribution contains reusable application behavior and generic
provider adapters. It does not contain an Intelligent Iterations deployment,
customer data, credentials, private runner topology, or active production
workflows. Operators keep that material in a separate implementation
repository and pin the exact ii-os revision they deploy.

Except for the third-party components listed below, the repository is
licensed under [Apache-2.0](LICENSE). Its reusable media stack is included in
the same source tree under `packages/`: no sibling or private package checkout
is required.

## Architecture

The Flutter clients call an authenticated Dart API. The API owns
authorization, bounded workflow orchestration, audit receipts, and persistent
workspace state. Concrete Firebase, GitHub, storage, and relay adapters are
wired at the server composition root. External workers execute generated-media
and agent jobs; the API brokers signed references and lifecycle state rather
than proxying asset bytes or model credentials.

See [Architecture](docs/architecture.md) for a map of the codebase and a
recommended reading order.

## Development

Install Flutter stable 3.44.1 (the exact framework revision is pinned in
`.metadata`), then run the complete source gate:

```bash
tool/public_quality_gate.sh
```

It restores every package from its lockfile; analyzes and tests the app, the
Functions server, and each package under `packages/`; runs the front-end and
polling-cost audits; and compiles the web app. Continuous integration runs the
same script. The video render tests use `ffmpeg` and `ffprobe` from `PATH`. Golden screenshots are rendered on macOS/arm64, so the gate
excludes them; run `flutter test --tags golden` on that platform before
changing UI.

## Running without Firebase

ii-os compiles and starts without a Firebase project, cloud account, or
credential. With no configuration the app uses the placeholder options in
`lib/config/app_config.dart` and opens on the sign-in screen; signing in needs a
backend.

```bash
flutter run -d chrome
II_FFMPEG_ALLOW_DEBUG_FALLBACK=true flutter build apk --debug
```

- **Android:** `android/app/google-services.json` is optional. The Google
  Services Gradle plugin is applied only when that file exists. Debug builds
  use a checksum-pinned FFmpeg engine when
  `II_FFMPEG_ALLOW_DEBUG_FALLBACK=true`; release builds must supply a
  source-built engine (see `packages/ii_ffmpeg_universal`).
- **iOS:** no `GoogleService-Info.plist` is required. Google Sign-In needs
  your reversed client ID in place of the
  `com.googleusercontent.apps.your-ios-client-id` URL scheme in
  `ios/Runner/Info.plist`.
- **Connecting a backend:** pass your Firebase web configuration as
  `--dart-define` values: `II_OS_FIREBASE_API_KEY`, `II_OS_FIREBASE_APP_ID`,
  `II_OS_FIREBASE_MESSAGING_SENDER_ID`, `II_OS_FIREBASE_PROJECT_ID`,
  `II_OS_FIREBASE_AUTH_DOMAIN`, and optionally `II_OS_FIREBASE_WEB_VAPID_KEY`,
  `II_OS_GOOGLE_IOS_CLIENT_ID`, and `II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID`.
  The API base defaults to the same-origin `/api` and can be changed with
  `II_OS_CONTROL_API_BASE_URL`.

The platform shells use generic application identifiers. A release operator
supplies its own Android application ID, iOS bundle ID, signing material,
Firebase configuration, and hosting settings from the implementation
repository.

## Deployment

No active deployment workflow is enabled by this source tree. The files under
`examples/workflows/` are deliberately inert templates: each stops until an
operator supplies a reviewed toolchain or deployment adapter. See
[Deployment boundary](docs/deployment.md) before copying one into
`.github/workflows/`.

Cross-repository agent publication is disabled by default. Deployments that
need it set an exact coordinator through
`II_OS_AGENT_COORDINATOR_REPOSITORY` and a comma-separated allowlist through
`II_OS_AGENT_PUBLICATION_TARGETS`.

## Third-party components

| Path | Origin | License |
| --- | --- | --- |
| `packages/ii_ffmpeg_universal/third_party/ffmpeg_kit_flutter_mobile_full/` | Modified FFmpegKit Flutter plugin | LGPL-3.0 (`LICENSE`, with the GPL-3.0 text it extends in `COPYING`) |
| `packages/ii_ffmpeg_universal/assets/web/ii_ffmpeg_universal_worker.js` | Adapted from `@ffmpeg/ffmpeg` 0.12.15 | MIT (`packages/ii_ffmpeg_universal/docs/third-party-notices.md`) |
| `packages/ii_ffmpeg_universal/tool/patches/ffmpeg-5.1-web.patch` | Modified excerpt of FFmpeg n5.1.10 `fftools`, adapting ffmpeg.wasm `f876f907` | LGPL-2.1-or-later (patch header and `packages/ii_ffmpeg_universal/docs/third-party-notices.md`) |
| `packages/ii_os_design_system/fonts/Manrope-*.ttf` | Subsets of the Manrope typeface | SIL Open Font License 1.1 (`Manrope-LICENSE.txt`) |

No FFmpeg binaries are committed. Release engines are compiled with GPL and
nonfree components disabled; the debug-only fallback downloads a
checksum-pinned prebuilt engine. See
`packages/ii_ffmpeg_universal/docs/native-engine-provenance.md`. Asset origins
are listed in [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md).

## Security

Please report vulnerabilities privately as described in
[SECURITY.md](SECURITY.md). Do not place secrets, customer data, or private
deployment topology in issues or pull requests.

## Intelligent Iterations

ii-os is maintained by Intelligent Iterations. Project and security contact
details are documented in this repository.
