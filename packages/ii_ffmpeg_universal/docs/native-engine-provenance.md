# Native engine provenance and distribution gate

Reviewed 2026-07-20. Any engine, version, URL, enabled library, or checksum
change requires a fresh review and live platform run.

## Android and iOS

The vendored mobile adapter under
`third_party/ffmpeg_kit_flutter_mobile_full/` is derived from
[`ffmpeg_kit_flutter_new_full` 2.4.1](https://pub.dev/packages/ffmpeg_kit_flutter_new_full),
which points to the [`sk3llo/ffmpeg_kit_flutter`](https://github.com/sk3llo/ffmpeg_kit_flutter)
source. The ii-os changes remove macOS and Windows plugin registration,
migrate the Android adapter to Flutter 3.44 built-in Kotlin, and make native
artifact verification mandatory. The mobile lifecycle patch also prevents completion
callbacks from reaching a detached Flutter engine, cancels native sessions on
detach, admits only one Flutter engine per process, and does not transfer that
ownership until native sessions and Android executor work have stopped on a
background cleanup path. Flutter's platform thread never waits for that join. A
second engine receives a structured unsupported-engine error while cleanup is
pending and can claim ownership on a later method or event retry after cleanup
finishes; a failed detach join leaves ownership locked until process exit. Native completion
events include the terminal return code so Dart does not query an evictable
process-global history after receiving completion.

The adapter source starts from the exact pub archive
`ffmpeg_kit_flutter_new_full-2.4.1.tar.gz`, SHA-256
`9f9625224387cbd5fad680f16fc20c303bff0fcd083c89c7fd19bd8f78ab18f2`.
The package's older Maven AAR and GitHub XCFramework hashes remain available
only through the explicit `II_FFMPEG_ALLOW_DEBUG_FALLBACK=true` development
escape hatch. Normal and release builds require locally built, attested
artifacts; release tasks reject the fallback even if it was requested.
The vendored mobile adapter intentionally has no Swift Package manifest.
iOS consumption uses CocoaPods so its prepare hook can require and verify the
locally built, attested XCFramework archives; enabling Flutter SwiftPM for this
plugin is unsupported because it would bypass that release-engine gate.

`tool/mobile_engine_lock.json` is the authoritative native build input. It pins:

- FFmpegKit build recipe (`arthenica/ffmpeg-kit-next`) commit
  `3e223118e6e8fb6208693ecf3952e77cd096f587`;
- FFmpeg n8.1.2 source commit
  `38b88335f99e76ed89ff3c93f877fdefce736c13`;
- every Android/iOS font and subtitle dependency to an exact Git commit;
- Android NDK `28.2.13676358`, compile SDK 35, Java target 17, iOS 14.0, all
  four Android ABIs, and the exact XCFramework library set;
- the Homebrew/core commit, formula bytes, bottle versions, and executable
  versions used to supply the Apple build tools;
- a network-disabled, shared-library profile with GPL, nonfree, TLS, x264,
  x265, Xvid, vid.stab, and Rubber Band enablement forbidden.

`tool/build_mobile_engine.py` clones only those commits, records every tracked
license, builds Android and iOS locally, embeds the source ledger and notices,
and invokes `tool/verify_mobile_engine.py` before emitting an attestation. The
Android wrapper is compiled directly with `javac` against the image-owned SDK
35 `android.jar`; the deterministic AAR assembler does not run the upstream
Gradle publishing project or resolve its plugins. Its ledger records the actual
SDK JAR hash, NDK revision, Java target, and `javac` identity before that ledger
is embedded. The verifier requires the exact JNI library set for every ABI,
checks every ELF class/type/machine and SONAME identity, resolves every
`DT_NEEDED`, `DT_FILTER`, and `DT_AUXILIARY` loader edge against the packaged
closure or exact Android system-library allowlist, rejects RPATH/RUNPATH, and
reads the FFmpeg configuration and n8.1.2 marker from each libavutil variant.
For iOS it validates every XCFramework
`Info.plist`, exact device/simulator identifiers and binary paths, and every
arm64/arm64e/x86_64 Mach-O dependency--including lazy-load commands--platform,
and minimum-deployment slice. It also rejects forbidden flags, absent release
flags, unreviewed dynamic dependencies, and absent licenses.

An iOS build additionally requires `apple-build-tools.json` as an explicit
input. That report binds the clean pinned Homebrew/core checkout, each selected
formula and install receipt, a content-and-mode digest over every installed
formula file and symlink, every locked Homebrew runtime dependency, the exact
executable selected through `PATH`, and the selected Xcode compiler, linker,
archive tools, complete iPhoneOS SDK file/mode/symlink tree, SDK settings, and
system launcher digests. Tree inputs are read through descriptor-relative,
no-follow traversal and rejected if an entry changes or escapes its root.
The lock, install receipts, and supplied attestation are each parsed and
digested from the same identity-pinned read.
The builder recomputes the complete report before preparation, immediately
before compilation, and after compilation. It records the report's SHA-256 in
both the source ledger and engine attestation, so the attested engine cannot
be separated from the tool closure that produced it. A build job that creates a
disposable Homebrew tap should keep its ownership record outside the Git
checkout and bind cleanup to the tap directory's device and inode; that
preserves a clean checkout for attestation without weakening destructive-target
ownership.

The attestation assumes the build runs in an exclusive, ephemeral runtime
started from a pinned base image. Identity-pinned reads and the before/after
closure checks reject stale, redirected, linked, or persistently mutated inputs. They do not
claim to defeat a malicious privileged co-tenant that can replace compiler or
SDK bytes during compilation and restore them before the closing check; such a
host invalidates the evidence. Cleanup ownership prevents accidental target
collisions within that exclusive runtime rather than defending against hostile
root-level namespace replacement.

The Android application consumes the just-built AAR through an absolute path
and SHA-256 supplied as `II_FFMPEG_ANDROID_AAR` and
`II_FFMPEG_ANDROID_AAR_SHA256`. The iOS setup consumes the just-built
deterministic XCFramework archives through an absolute directory plus their
attestation, supplied as `II_FFMPEG_IOS_ARCHIVE_DIR` and
`II_FFMPEG_IOS_ATTESTATION`. Both integrations reject links, missing artifacts,
and digest mismatches.

An operator's release gate should require the source ledger, notices,
verification JSON, application runtime proof, and runtime cleanup proof for
each build, and should keep the release application archives themselves rather
than only manifests that describe them. If the operator publishes signed build
provenance, every kept artifact should be one of its subjects, and the gate
should verify the signer identity, then re-read and rehash each artifact from
durable storage before it passes. Each application binding check should open
the APK/app/browser or desktop archive and compare its embedded engine files
with the attested source-built engine bytes.

## Desktop

Linux and macOS require a `FfmpegDesktopBundle` containing absolute
`ffmpeg` and `ffprobe` paths, every non-system dynamic dependency, CPU
architecture, loader name, and SHA-256 value. `tool/build_desktop_engine.py` builds FFmpeg from the exact
mobile source lock with network and autodetection disabled, recursively resolves
non-system dependencies, audits ELF/Mach-O identities, performs any required
Mach-O load-command localization and signing at build time, and emits the
manifest, archive, source ledger, notices, and attestation. Shipping apps bundle
those files as assets and bind the manifest hash at compile time.

On macOS this execution model intentionally requires the host application to
run without App Sandbox because it starts the attested engine executables as
child processes. A sandboxed Mac App Store host needs a separately designed,
signed, and reviewed helper boundary; this package does not claim that the
process backend is App-Sandbox compatible. Packaging evidence rejects a
macOS fixture that misleadingly carries the App Sandbox entitlement.

The runtime loader rejects links and non-regular files and verifies the exact
manifest and every closure digest. The backend stages and rehashes the complete
closure into one owned directory and seals it through libc. No runtime
`otool`, `readelf`, `install_name_tool`, `codesign`, PATH lookup, or shell is
required. Each application still owns codec-license review, scanning, update
cadence, and protected installation.

Flutter Driver cannot drive non-web release binaries, so live integration runs
use Linux and macOS profile application bundles. Release bundles can only be
verified at package level: an operator should reconstruct and verify each
desktop engine attestation, archive, manifest, source ledger, notices file, and
application manifest from the exact artifact bytes, and should label those
release bundles as package-verified rather than claiming they were executed.

## Distribution obligations

The vendored adapter source carries its upstream LGPL-3.0 license. FFmpeg and
linked optional libraries each retain their own licenses. The upstream `full`
variant is selected instead of a `full-gpl` variant, but that name is not
sufficient release evidence by itself.

Before distributing an Android/iOS application, the release owner must archive
the engine's runtime package/configuration report, dependency license manifest,
corresponding-source location, notices, relink/reverse-engineering terms, and
the exact application artifact hashes. Legal review must confirm the chosen
static/dynamic linking and delivery method satisfies LGPL and every enabled
library. A store or customer release fails closed when that evidence is absent.
Operator CI may validate development artifacts; passing simulator/emulator and
compile-only lanes are not a legal approval or a production store-signing gate.

No browser core is shipped inside this Dart package. The locked build recipe
uses FFmpeg 5.1.10 plus exact libvpx, Opus, libass, FreeType, FriBidi, HarfBuzz,
and zlib sources. Network, pthread, GPL, nonfree, TLS, x264, and x265 enablement
is forbidden. The builder emits third-party notices and source, patch,
toolchain, configuration, and artifact hashes; the verifier checks the Wasm
memory declaration and reviewed single-thread JavaScript shape. An application
that promotes those external artifacts must retain the corresponding source
and complete its own codec/linkage/license review. `FfmpegWebBundle` binds that
choice to exact runtime hashes but does not decide distribution obligations.

The packaged quota-enforcing class worker is adapted from
`@ffmpeg/ffmpeg` 0.12.15 under the MIT license. Its source remains readable at
`assets/web/ii_ffmpeg_universal_worker.js`; the upstream copyright and license
notice are recorded in `docs/third-party-notices.md`.
