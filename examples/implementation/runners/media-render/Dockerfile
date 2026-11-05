# syntax=docker/dockerfile:1
#
# media-render runner: CPU video-editor exports. It runs ii-os's own
# tool/render_editor_manifest.dart, so the image carries the ii-os source tree
# of the version your dashboard runs. Build from the kit root and pass a clean
# checkout of that ii-os commit as the `ii-os` build context:
#
#   docker build -f runners/media-render/Dockerfile \
#     --build-context ii-os=/path/to/ii-os-checkout \
#     -t registry.example.com/ii-os/media-render:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_MEDIA_RENDER to the pushed reference
# pinned by digest. The workflow runs it with no network; every package and
# engine artifact is resolved here, at build time.
FROM debian:bookworm-20261027-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3

# The Flutter commit ii-os builds with (its .metadata revision).
ARG FLUTTER_REVISION=924134a44c189315be2148659913dda1671cbe99

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/opt/pub-cache \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    CI=true \
    II_OS_SOURCE_ROOT=/opt/ii-os \
    PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates curl ffmpeg file git python3 tini unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*'

RUN git init --quiet "${FLUTTER_HOME}" \
    && git -C "${FLUTTER_HOME}" remote add origin https://github.com/flutter/flutter.git \
    && git -C "${FLUTTER_HOME}" fetch --quiet --depth 1 origin "${FLUTTER_REVISION}" \
    && git -C "${FLUTTER_HOME}" checkout --quiet --detach "${FLUTTER_REVISION}" \
    && test "$(git -C "${FLUTTER_HOME}" rev-parse HEAD)" = "${FLUTTER_REVISION}" \
    && flutter config --no-analytics \
    && flutter precache --universal --linux --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia \
    && flutter --version

COPY --from=ii-os . /opt/ii-os

RUN cd /opt/ii-os \
    && test -f tool/render_editor_manifest.dart \
    && flutter pub get --enforce-lockfile \
    && chmod -R a+rwX /opt/flutter /opt/pub-cache /opt/ii-os

COPY runners/common /opt/ii-os-runner/common
COPY runners/media-render /opt/ii-os-runner/media-render

RUN python3 /opt/ii-os-runner/media-render/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/media-render/entrypoint.py"]
CMD ["run", "--task", "editor-render"]
