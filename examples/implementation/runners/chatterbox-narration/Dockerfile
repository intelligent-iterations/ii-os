# syntax=docker/dockerfile:1
#
# chatterbox-narration runner. Build from the kit root so the shared runner
# library is in the build context:
#
#   docker build -f runners/chatterbox-narration/Dockerfile -t registry.example.com/ii-os/chatterbox-narration:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_CHATTERBOX_NARRATION to the pushed
# reference pinned by digest (registry.example.com/ii-os/chatterbox-narration@sha256:...).
# No model weights are baked in: the workflow mounts
# ${II_OS_MODEL_ROOT}/chatterbox-narration read-only at /models and runs the
# container with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ARG CHATTERBOX_REVISION=ab55923c27757c90cfcc407baa57dc25a7d25217

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/opt/venv/lib/python3.12/site-packages/nvidia/cu13 \
    LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PYTHONPATH=/opt/ii-os-runner/chatterbox-narration \
    PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/bin:/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates ffmpeg git libsndfile1 patch python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Install all dependencies, including source build backends, from hashed locks.
COPY runners/chatterbox-narration/requirements-build.lock.txt runners/chatterbox-narration/requirements.lock.txt /opt/ii-os-runner/chatterbox-narration/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps -r /opt/ii-os-runner/chatterbox-narration/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --no-build-isolation \
      -r /opt/ii-os-runner/chatterbox-narration/requirements.lock.txt

COPY runners/common /opt/ii-os-runner/common
COPY runners/chatterbox-narration /opt/ii-os-runner/chatterbox-narration

# Apply the reviewed headless dependency/cache patch to immutable upstream source.
RUN git clone --filter=blob:none --no-checkout https://github.com/resemble-ai/chatterbox.git /opt/chatterbox \
    && git -C /opt/chatterbox checkout --detach "${CHATTERBOX_REVISION}" \
    && test "$(git -C /opt/chatterbox rev-parse HEAD)" = "${CHATTERBOX_REVISION}" \
    && git -C /opt/chatterbox apply --check /opt/ii-os-runner/chatterbox-narration/patches/headless-security.patch \
    && git -C /opt/chatterbox apply /opt/ii-os-runner/chatterbox-narration/patches/headless-security.patch \
    && pip install --no-deps --no-build-isolation /opt/chatterbox \
    && rm -rf /opt/chatterbox/.git \
    && patch --batch --forward -p1 -d /opt/venv/lib/python3.12/site-packages < /opt/ii-os-runner/chatterbox-narration/patches/perth-resources.patch \
    && python3 -c "import perth; assert perth.PerthImplicitWatermarker is not None; perth.PerthImplicitWatermarker()" \
    && pip check \
    && python3 -c "import chatterbox.tts_turbo, soundfile, torch; assert torch.__version__.startswith('2.13.0'), torch.__version__" \
    && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libmp3lame \
    && python3 /opt/ii-os-runner/chatterbox-narration/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/chatterbox-narration/entrypoint.py"]
CMD ["run", "--task", "text-to-speech"]
