# syntax=docker/dockerfile:1
#
# acestep-song runner. Build from the kit root so the shared runner library is
# in the build context:
#
#   docker build -f runners/acestep-song/Dockerfile -t registry.example.com/ii-os/acestep-song:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_ACESTEP_SONG to the pushed reference
# pinned by digest (registry.example.com/ii-os/acestep-song@sha256:...).
# No model weights are baked in: the workflow mounts
# ${II_OS_MODEL_ROOT}/acestep-song read-only at /models and runs the container
# with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ARG ACESTEP_REVISION=ca1e85fe9430179831e6bc6be790c332190a3866

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/opt/venv/lib/python3.12/site-packages/nvidia/cu13 \
    LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PYTHONPATH=/opt/ii-os-runner/acestep-song \
    PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/bin:/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates ffmpeg git libsndfile1 patch python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Install all dependencies, including source build backends, from hashed locks.
COPY runners/acestep-song/requirements-build.lock.txt runners/acestep-song/requirements.lock.txt /opt/ii-os-runner/acestep-song/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps -r /opt/ii-os-runner/acestep-song/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --no-build-isolation \
      -r /opt/ii-os-runner/acestep-song/requirements.lock.txt

COPY runners/common /opt/ii-os-runner/common
COPY runners/acestep-song /opt/ii-os-runner/acestep-song

# Apply the reviewed headless dependency/cache patch to immutable upstream source.
RUN git clone --filter=blob:none --no-checkout https://github.com/ace-step/ACE-Step-1.5.git /opt/ACE-Step-1.5 \
    && git -C /opt/ACE-Step-1.5 checkout --detach "${ACESTEP_REVISION}" \
    && test "$(git -C /opt/ACE-Step-1.5 rev-parse HEAD)" = "${ACESTEP_REVISION}" \
    && git -C /opt/ACE-Step-1.5 apply --check /opt/ii-os-runner/acestep-song/patches/headless-security.patch \
    && git -C /opt/ACE-Step-1.5 apply /opt/ii-os-runner/acestep-song/patches/headless-security.patch \
    && pip install --no-deps --no-build-isolation -e /opt/ACE-Step-1.5 /opt/ACE-Step-1.5/acestep/third_parts/nano-vllm \
    && ln -s /opt/venv /opt/ACE-Step-1.5/.venv \
    && rm -rf /opt/ACE-Step-1.5/checkpoints /opt/ACE-Step-1.5/.cache \
    && ln -s /tmp/acestep/checkpoints /opt/ACE-Step-1.5/checkpoints \
    && ln -s /tmp/acestep/cache /opt/ACE-Step-1.5/.cache \
    && rm -rf /opt/ACE-Step-1.5/.git \
    && patch --batch --forward -p1 -d /opt/venv/lib/python3.12/site-packages < /opt/ii-os-runner/acestep-song/patches/pytorch-wavelets-resources.patch \
    && python3 -c "from pytorch_wavelets.dtcwt.coeffs import qshift; assert len(qshift('qshift_a')) == 8" \
    && pip check \
    && python3 /opt/ii-os-runner/acestep-song/validate_model_initialization.py \
    && python3 -c "import acestep.model_downloader, acestep.api.server_cli, torch; assert torch.__version__.startswith('2.13.0'), torch.__version__" \
    && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libmp3lame \
    && python3 /opt/ii-os-runner/acestep-song/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
# Prove the complete API imports as its runtime user without model initialization.
RUN mkdir -p /tmp/acestep/cache \
    && ACESTEP_NO_INIT=true python3 -c "import acestep.api_server" \
    && rm -rf /tmp/acestep
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/acestep-song/entrypoint.py"]
CMD ["run", "--task", "text-to-song"]
