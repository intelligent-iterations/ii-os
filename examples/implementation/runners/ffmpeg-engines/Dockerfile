# syntax=docker/dockerfile:1
#
# Builds the FFmpeg web (wasm) and Android (AAR) engines from this
# repository's embedded package, fetching only the exact sources pinned in its
# tool/web_engine_lock.json and tool/mobile_engine_lock.json. Nothing prebuilt
# is downloaded except the checksum-pinned Android command-line tools.
#
# The build context is the package directory, not the repository root:
#
#   docker build --file runners/ffmpeg-engines/Dockerfile \
#     --build-arg II_FFMPEG_ENGINE_SOURCE_SHA="$(git rev-parse HEAD)" \
#     packages/ii_ffmpeg_universal
#
# The result holds /out/web and /out/android. Each carries its artifacts,
# build attestation, source ledger, third-party notices, verification report,
# and a source-revision file naming the commit it was built from. Record that
# commit and the AAR digest in tool/ffmpeg-engine-pins. See
# docs/mobile-release.md, including the LGPL obligations that come with
# distributing these binaries.

FROM node:22-bookworm@sha256:a25c9934ff6382cd4f08b6bc26c82bf4ea69b1e6f8dabfb2ead457374127c365

ARG II_FFMPEG_ENGINE_SOURCE_SHA
ARG II_FFMPEG_BUILD_JOBS=4
ARG ANDROID_COMMANDLINE_TOOLS=15859902
ARG ANDROID_COMMANDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    autoconf automake autopoint bison build-essential ca-certificates clang \
    cmake curl ffmpeg flex gettext git jq libtool libtool-bin meson nasm \
    ninja-build openjdk-17-jdk-headless openssl patch pkg-config python3 \
    rsync unzip xz-utils yasm zip \
  && rm -rf /var/lib/apt/lists/*

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk

COPY . /src/ii_ffmpeg_universal

RUN set -eux; \
  printf '%s\n' "$II_FFMPEG_ENGINE_SOURCE_SHA" | grep -Eqx '[0-9a-f]{40}'; \
  archive="/tmp/commandlinetools-linux-${ANDROID_COMMANDLINE_TOOLS}_latest.zip"; \
  curl -fsSL --retry 3 \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_COMMANDLINE_TOOLS}_latest.zip" \
    -o "$archive"; \
  printf '%s  %s\n' "$ANDROID_COMMANDLINE_TOOLS_SHA256" "$archive" | sha256sum -c -; \
  install -d "$ANDROID_SDK_ROOT/cmdline-tools"; \
  unzip -q "$archive" -d "$ANDROID_SDK_ROOT/cmdline-tools"; \
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" \
    "$ANDROID_SDK_ROOT/cmdline-tools/latest"; \
  rm -f "$archive"; \
  compile_sdk="$(jq -er .toolchains.android_compile_sdk \
    /src/ii_ffmpeg_universal/tool/mobile_engine_lock.json)"; \
  ndk_revision="$(jq -er .toolchains.android_ndk_revision \
    /src/ii_ffmpeg_universal/tool/mobile_engine_lock.json)"; \
  yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true; \
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --install \
    "platforms;android-$compile_sdk" "ndk;$ndk_revision"; \
  test -f "$ANDROID_SDK_ROOT/platforms/android-$compile_sdk/android.jar"; \
  test -x "$ANDROID_SDK_ROOT/ndk/$ndk_revision/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"

RUN set -eux; \
  II_FFMPEG_BUILD_JOBS="$II_FFMPEG_BUILD_JOBS" python3 \
    /src/ii_ffmpeg_universal/tool/build_web_engine.py \
    --workspace /tmp/ffmpeg-web-engine; \
  python3 /src/ii_ffmpeg_universal/tool/verify_web_engine.py \
    --artifacts /tmp/ffmpeg-web-engine/artifacts \
    --ledger /tmp/ffmpeg-web-engine/artifacts/source-ledger.json \
    --lock /src/ii_ffmpeg_universal/tool/web_engine_lock.json; \
  install -d -m 0755 /out/web/artifacts; \
  for artifact in build-attestation.json source-ledger.json \
      THIRD_PARTY_NOTICES.txt verification.json ffmpeg.js ffmpeg-core.js \
      ffmpeg-core.wasm; do \
    install -m 0644 "/tmp/ffmpeg-web-engine/artifacts/$artifact" \
      "/out/web/artifacts/$artifact"; \
  done; \
  printf '%s\n' "$II_FFMPEG_ENGINE_SOURCE_SHA" >/out/web/source-revision; \
  rm -rf /tmp/ffmpeg-web-engine

RUN set -eux; \
  ndk_revision="$(jq -er .toolchains.android_ndk_revision \
    /src/ii_ffmpeg_universal/tool/mobile_engine_lock.json)"; \
  export ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk/$ndk_revision"; \
  II_FFMPEG_BUILD_JOBS="$II_FFMPEG_BUILD_JOBS" python3 \
    /src/ii_ffmpeg_universal/tool/build_mobile_engine.py android \
    --workspace /tmp/ffmpeg-android-engine; \
  artifacts=/tmp/ffmpeg-android-engine/artifacts; \
  aar="$artifacts/ii-ffmpeg-mobile-android.aar"; \
  python3 /src/ii_ffmpeg_universal/tool/verify_mobile_engine.py \
    --lock /src/ii_ffmpeg_universal/tool/mobile_engine_lock.json \
    android --archive "$aar" --release \
    >"$artifacts/consumer-verification.json"; \
  aar_sha="$(jq -er '.artifacts[] | select(.path == "ii-ffmpeg-mobile-android.aar") | .sha256' \
    "$artifacts/build-attestation.json")"; \
  test "$(sha256sum "$aar" | awk '{print $1}')" = "$aar_sha"; \
  install -d -m 0755 /out/android/artifacts; \
  for artifact in build-attestation.json source-ledger.json \
      THIRD_PARTY_NOTICES.txt verification.json consumer-verification.json \
      ii-ffmpeg-mobile-android.aar; do \
    install -m 0644 "$artifacts/$artifact" "/out/android/artifacts/$artifact"; \
  done; \
  printf '%s\n' "$II_FFMPEG_ENGINE_SOURCE_SHA" >/out/android/source-revision; \
  rm -rf /tmp/ffmpeg-android-engine
