# syntax=docker/dockerfile:1
#
# seedvr2-video runner. Build from the kit root so the shared runner library
# is in the build context:
#
#   docker build -f runners/seedvr2-video/Dockerfile -t registry.example.com/ii-os/seedvr2-video:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_SEEDVR2_VIDEO to the pushed reference
# pinned by digest (registry.example.com/ii-os/seedvr2-video@sha256:...).
# No model weights are baked in: the workflow mounts
# ${II_OS_MODEL_ROOT}/seedvr2-video read-only at /models and runs the
# container with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ARG COMFYUI_REVISION=5f0c4e18cb7e98f0e7c46c2c7ce928d641351e67
ARG SEEDVR2_NODE_REVISION=4490bd1f482e026674543386bb2a4d176da245b9
ARG SEEDVR2_PATCH_SHA256=87ac557d7b73061dd9b5abcf1ca43c3a62abdb7c8ec3a98199b185e4525c997c

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/opt/venv/lib/python3.12/site-packages/nvidia/cu13 \
    LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/bin:/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ffmpeg/ffprobe probe the source, put its audio back and cut the poster.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates ffmpeg git libgl1 libglib2.0-0 python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Every Python package comes from this runner's lock files, pinned by version
# and sha256 and installed without dependency resolution: the installer
# (requirements-build.lock.txt) first, then everything the runner imports
# (requirements.lock.txt). See README.md to recompile them. The CUDA 13.0
# packages and toolkit come from PyPI and are also hash-pinned in the lock. The
# one source-only package, antlr4-python3-runtime (omegaconf needs it), builds
# with the hash-pinned setuptools from the build lock rather than one fetched
# for the build.
COPY runners/seedvr2-video/requirements-build.lock.txt runners/seedvr2-video/requirements.lock.txt /opt/ii-os-runner/seedvr2-video/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps -r /opt/ii-os-runner/seedvr2-video/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --no-build-isolation \
      --index-url https://pypi.org/simple \
      -r /opt/ii-os-runner/seedvr2-video/requirements.lock.txt

RUN git clone --filter=blob:none --no-checkout https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && git -C /opt/ComfyUI checkout --detach "${COMFYUI_REVISION}" \
    && test "$(git -C /opt/ComfyUI rev-parse HEAD)" = "${COMFYUI_REVISION}" \
    && rm -rf /opt/ComfyUI/.git

# The SeedVR2 custom node at a pinned commit, plus one small patch: without it
# the node plants a stub `flash_attn` module when flash-attn is not installed,
# which newer transformers/diffusers then try to use. The patch is hash-checked
# and must touch exactly one file.
COPY runners/seedvr2-video/seedvr2-transformers-5-flash-attn.patch /tmp/seedvr2-node.patch
RUN node=/opt/ComfyUI/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler \
    && git clone --filter=blob:none --no-checkout https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git "${node}" \
    && git -C "${node}" checkout --detach "${SEEDVR2_NODE_REVISION}" \
    && test "$(git -C "${node}" rev-parse HEAD)" = "${SEEDVR2_NODE_REVISION}" \
    && echo "${SEEDVR2_PATCH_SHA256}  /tmp/seedvr2-node.patch" | sha256sum --check --strict - \
    && git -C "${node}" apply --check /tmp/seedvr2-node.patch \
    && git -C "${node}" apply /tmp/seedvr2-node.patch \
    && test "$(git -C "${node}" diff --name-only)" = "src/optimization/compatibility.py" \
    && rm -rf "${node}/.git" /tmp/seedvr2-node.patch

# ComfyUI's own requirements and the node's dependencies (with transformers
# and huggingface-hub, which they interact with) were resolved together into
# requirements.lock.txt, a set known to work together on this Python.
RUN python3 -m compileall -q /opt/ComfyUI/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler

# The node keeps its validation cache in its default model folder. Point that
# folder at a scratch path the unprivileged runner user can write; the weights
# themselves are found through /models/SEEDVR2 (extra_model_paths.yaml).
RUN ln -s /tmp/ii-os-seedvr2-cache /opt/ComfyUI/models/SEEDVR2

COPY runners/common /opt/ii-os-runner/common
COPY runners/seedvr2-video /opt/ii-os-runner/seedvr2-video

RUN pip check \
    && ffprobe -version >/dev/null \
    && python3 /opt/ii-os-runner/seedvr2-video/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/seedvr2-video/entrypoint.py"]
CMD ["run", "--task", "video-upscale"]
