# Mobile releases and FFmpeg engines

This guide covers publishing your own build of the ii-os mobile app:

- **Android** to the Google Play internal testing track;
- **iOS** to App Store Connect for TestFlight processing;
- the **FFmpeg engines** those builds embed, which you build and pin
  yourself.

Everything here is a template. The release workflows ship inert under
`examples/implementation/.github/workflows/`, and every account, runner,
path, and credential is a setting you supply. Nothing in this repository
publishes an app, signs a binary, or downloads a prebuilt engine on its own.

## How a release flows

1. A signed-in operator presses **Update** in the Android or iOS app.
2. The app asks the ii-os API to dispatch
   `<II_OS_MOBILE_UPDATE_REPOSITORY>#mobile-update-android` (or
   `#mobile-update-ios`): the catalog entry with that id in the repository
   your deployment names in `II_OS_MOBILE_UPDATE_REPOSITORY`. The workspace
   must have enabled that workflow, and the member needs permission to trigger
   jobs. An empty `II_OS_MOBILE_UPDATE_REPOSITORY` hides the button.
3. The catalog entry dispatches `mobile-update-android.yml` or
   `mobile-update-ios.yml`. These wrappers take no client-controlled input.
4. The wrapper calls `release-android.yml` or `release-ios.yml` with
   `publish: true`. Those run the scripts under `tool/` against the reviewed
   head of your release branch.

Dispatching `release-android.yml` directly builds a validation bundle with a
throwaway key and never contacts Google Play. Dispatching `release-ios.yml`
directly only queries the processing status of one App Store Connect build.
The upload steps refuse any workflow other than the matching wrapper.

## Adopting the workflow kit

The release workflows build the app from the repository they run in, so they
need a fork of ii-os:

1. Fork this repository and choose a release branch, such as `main`.
2. Move the contents of `examples/implementation/` to the root of your fork.
   If your fork already has a `.ii-os/catalog.yaml`, merge the two
   `mobile-update-*` entries into it and keep their ids exactly. Delete the
   catalog entries and workflows you do not serve.
3. Fill in the settings below, then review the workflows as you would any
   code that holds signing credentials.
4. Point your ii-os deployment's `II_OS_MOBILE_UPDATE_REPOSITORY` at the fork
   and enable the two update workflows for your workspace.

Use protected GitHub environments named `mobile-release-android` and
`mobile-release-ios` for the release secrets, restricted to your release
branch, with required reviewers if you want a human approval per release.

## Prerequisites

| Purpose | Runner setting | Requirements |
| --- | --- | --- |
| Engine build | `II_OS_CPU_RUNS_ON` | Linux x86_64 with Docker, network access to the pinned sources, and the engine store directory. A full build takes hours. |
| Android release | `II_OS_CPU_RUNS_ON` | A disposable Linux runner: a container-based runner or a GitHub-hosted runner. The toolchain bootstrap installs system packages and refuses any other machine. It must be able to read the engine store. |
| iOS release | `II_OS_MACOS_RUNS_ON` | Apple Silicon macOS with Xcode (iPhoneOS SDK 26 or later), Homebrew, CocoaPods, Ruby, Python 3, and `jq`. Use a disposable machine or VM: the release creates and removes a temporary keychain and provisioning profile. |

Each `*_RUNS_ON` value is JSON for `runs-on`, for example
`["self-hosted", "linux", "x64"]` or `"ubuntu-latest"`. Running these jobs
on GitHub-hosted runners in a private repository consumes billed Actions
minutes; check your plan first. The workflows create no Actions artifacts or
caches.

Accounts you need:

- a Google Play developer account and an app with your application id;
- a Google Cloud project for the Play upload identity, and a Firebase project
  with Android and iOS apps registered;
- an Apple Developer Program membership, an App Store Connect API key, an
  Apple Distribution certificate, and an App Store provisioning profile for
  your bundle id with the production push entitlement.

## Settings

Repository variables (`vars.*`):

| Variable | Used by | Meaning |
| --- | --- | --- |
| `II_OS_WORKFLOW_REPOSITORY` | all | `owner/name` of your fork. The tools refuse to run anywhere else, and there is no default. |
| `II_OS_WORKFLOW_BRANCH` | all | Your release branch. Releases run only from its reviewed head. |
| `II_OS_CPU_RUNS_ON` | engines, Android | `runs-on` JSON for Linux jobs. |
| `II_OS_MACOS_RUNS_ON` | iOS | `runs-on` JSON for macOS jobs. |
| `II_OS_FFMPEG_ENGINE_STORE` | engines, Android | Absolute directory on your Linux runners where engines are stored, one subdirectory per source commit. |
| `II_OS_RELEASE_EVIDENCE_DIR` | Android | Absolute directory on the Android runner that keeps each App Bundle and its engine evidence. |
| `II_OS_MOBILE_BUILD_NAME` | Android, iOS | Marketing version, such as `1.0.0`. Build numbers come from the wrapper's run number. |
| `II_OS_ANDROID_APPLICATION_ID` | Android | Your Android application id. |
| `II_OS_FIREBASE_EXPECTED_PROJECT_ID` | Android | Firebase project the Android configuration must belong to. |
| `II_OS_WEB_ORIGIN` | Android | HTTPS origin of your ii-os deployment; the app calls `<origin>/api`. |
| `II_OS_GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` | Android | Full Workload Identity provider resource name. |
| `II_OS_GOOGLE_PLAY_SERVICE_ACCOUNT` | Android | Service account email allowed to upload to Play. |
| `II_OS_IOS_BUNDLE_ID` | iOS | Your iOS bundle id. |
| `II_OS_APPLE_TEAM_ID` | iOS | Your Apple team id. |
| `II_OS_CONTROL_API_BASE_URL` | iOS | HTTPS base URL of your ii-os API. |
| `II_OS_FIREBASE_AUTH_DOMAIN` | iOS | Firebase Auth domain for your project. |

Secrets (`secrets.*`, ideally environment secrets):

| Secret | Environment | Meaning |
| --- | --- | --- |
| `II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64` | `mobile-release-android` | Base64 of your Play upload keystore. |
| `II_OS_ANDROID_KEY_PROPERTIES` | `mobile-release-android` | Three lines: `keyAlias`, `keyPassword`, `storePassword`. The workflow supplies `storeFile`. |
| `II_OS_ANDROID_GOOGLE_SERVICES_JSON` | `mobile-release-android` | Your `google-services.json`, with exactly one client for your application id. |
| `II_OS_APP_STORE_CONNECT_API_KEY` | `mobile-release-ios` | App Store Connect API private key (`.p8` text or its base64). |
| `II_OS_APP_STORE_CONNECT_API_KEY_ID` | `mobile-release-ios` | Its key id. |
| `II_OS_APP_STORE_CONNECT_ISSUER_ID` | `mobile-release-ios` | Its issuer id. |
| `II_OS_IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | `mobile-release-ios` | Base64 of the Apple Distribution certificate (`.p12`). |
| `II_OS_IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | `mobile-release-ios` | Its export password. |
| `II_OS_IOS_PROVISIONING_PROFILE_BASE64` | `mobile-release-ios` | Base64 of the App Store provisioning profile. |
| `II_OS_IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64` | `mobile-release-ios` | Base64 of your `GoogleService-Info.plist`. |

Every workflow checks its settings by name in its first step and stops with a
named error when one is missing. The scripts check again: `tool/` refuses a
missing `II_OS_WORKFLOW_REPOSITORY`, `II_OS_WORKFLOW_BRANCH`,
`II_OS_FIREBASE_EXPECTED_PROJECT_ID`, `II_FFMPEG_ANDROID_ENGINE_ROOT`,
`II_OS_RELEASE_EVIDENCE_DIR`, or `II_OS_ANDROID_UPLOAD_WORKFLOW` instead of
falling back to a built-in value.

## Producing your own attested engines

Release builds never download an FFmpeg engine. You build one from this
repository's `packages/ii_ffmpeg_universal`, review it, and pin it.

1. Dispatch `build-ffmpeg-engines.yml` from your release branch. It builds
   `runners/ffmpeg-engines/Dockerfile` with the package directory as context.
   The image fetches only the exact sources pinned in
   `tool/web_engine_lock.json` and `tool/mobile_engine_lock.json`, builds the
   web and Android engines, and verifies both.
2. The workflow copies the engines to
   `$II_OS_FFMPEG_ENGINE_STORE/<commit>/{web,android}` and makes them
   read-only. It refuses to overwrite an existing commit. Each platform
   directory holds the artifacts, `build-attestation.json`,
   `source-ledger.json`, `THIRD_PARTY_NOTICES.txt`, `verification.json`, and a
   `source-revision` file.
3. Review the notices and verification reports. Then copy
   `tool/ffmpeg-engine-pins.example` to `tool/ffmpeg-engine-pins`, fill in the
   two values from the workflow summary, and commit the file through review:

   ```text
   engine_source_revision=<the commit the engines were built from>
   android_aar_sha256=<SHA-256 of ii-ffmpeg-mobile-android.aar>
   ```

4. Android releases read the engine at
   `$II_OS_FFMPEG_ENGINE_STORE/<engine_source_revision>/android`.
   `tool/stage_pinned_android_engine.py` checks the AAR digest against the pin
   and the attestation, checks that the source ledger matches the current lock
   and builder, re-runs the release verifier, and records a binding.
   `tool/verify_android_aab_engine.py` then proves that the signed App Bundle
   contains exactly those native libraries.

The pins file is read only when it is committed and unmodified, so a runner
workspace or a repository variable cannot swap in a different engine. Rebuild
and re-pin whenever you change the engine locks or builder; the staging check
rejects an engine whose ledger no longer matches them.

The iOS engine is rebuilt on every iOS release.
`tool/prepare_ios_release_engine.sh` installs the Apple build tools from the
Homebrew commit pinned in the mobile lock into a run-owned tap, attests that
tool closure, builds and verifies the XCFramework archives, and hands them to
the iOS build through `II_FFMPEG_IOS_ARCHIVE_DIR` and
`II_FFMPEG_IOS_ATTESTATION`.

You may also sign engine artifacts. `packages/ii_ffmpeg_universal/tool/install_cosign.py`
installs a checksum-pinned Cosign release. Keyless signing records your
workflow identity in a public transparency log, so decide whether that suits
your repository before enabling it.

`packages/ii_ffmpeg_universal/docs/native-engine-provenance.md` describes the
build inputs, verification, and attestation in detail.

## Google Play setup

The Android upload uses GitHub OIDC and Workload Identity Federation; no
service-account key is stored in GitHub.

1. In your Google Cloud project, enable the Google Play Android Developer API
   and create a dedicated service account for uploads.
2. In Play Console, invite that service account and grant it permission to
   release to testing tracks.
3. Create a Workload Identity pool with a GitHub provider. Restrict the
   provider to your fork's repository and release branch, then grant that
   principal `roles/iam.workloadIdentityUser` on the service account.
4. Set `II_OS_GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` and
   `II_OS_GOOGLE_PLAY_SERVICE_ACCOUNT`.

Play Console may require the first bundle for a new app to be uploaded by
hand. Dispatch `release-android.yml` to check the build first: it uses a
throwaway key and a synthetic Firebase project, so it proves the toolchain and
engine without any credential.

Version codes are `1000000000` plus the wrapper's run number
(`tool/android_version_code.py`), which keeps them increasing.

## iOS setup

The release creates a temporary keychain and installs your provisioning
profile for the run, patches the Xcode project with your team, bundle id, and
profile, builds and verifies the signed IPA, uploads it with
`fastlane pilot`, and then restores the project and removes the keychain,
profile, and Firebase file. `tool/ios_app_store_release.sh` holds those steps,
and `tool/query_ios_app_store_build.rb` reads a build's processing status
without uploading.

## What the tools check

- `tool/workflow_source_identity.sh` binds every run to
  `II_OS_WORKFLOW_REPOSITORY`, `II_OS_WORKFLOW_BRANCH`, and the exact commit,
  and requires a clean checkout. A separate implementation repository that
  pins this source as a submodule can bind `II_OS_WORKFLOW_REPO_ROOT`,
  `II_OS_IMPLEMENTATION_SHA`, and `II_OS_SOURCE_SHA` together instead.
- `tool/upload_android_internal.sh` uploads only from the workflow named by
  `II_OS_ANDROID_UPLOAD_WORKFLOW`, on the release branch, in the configured
  repository. The iOS release job applies the same check to its wrapper.
- Signing material lives only in run-owned directories under `RUNNER_TEMP`,
  marked with the run id, and the cleanup steps delete only state carrying
  that run's marker.

Run the hermetic tests for all of this with `tool/release_tooling_test.sh`.
They need no network, account, or credential, and the public quality gate
runs them.

## Licensing obligations

Publishing these build scripts raises no license issue. Distributing the
binaries they produce does:

- The mobile engines are FFmpeg built as shared libraries with GPL, nonfree,
  and TLS components disabled, plus LGPL- and permissively licensed
  dependencies. The result is LGPL-2.1-or-later FFmpeg.
- The web engine is a single static WebAssembly build under the same
  constraints, which carries the LGPL obligations of static linking.
- The vendored Flutter plugin under
  `packages/ii_ffmpeg_universal/third_party/ffmpeg_kit_flutter_mobile_full/`
  is LGPL-3.0.

Before you distribute an app or a web build that contains an engine, keep for
that exact build its `THIRD_PARTY_NOTICES.txt`, source ledger, the
corresponding source (including the pinned upstream commits and patches), and
the relinking information the LGPL requires, and make them available as the
licenses require. Whether a given store's distribution terms are compatible
with LGPL-3.0 installation-information requirements, in particular for the
iOS App Store, is a legal question: get your own legal review before you ship
store binaries. Passing these workflows is not that approval.
