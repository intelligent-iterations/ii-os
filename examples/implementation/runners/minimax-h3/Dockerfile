# syntax=docker/dockerfile:1
#
# minimax-h3 runner: MiniMax H3 through a headless ComfyUI at a pinned commit,
# on PyTorch 2.13 with CUDA 13.0 and SageAttention compiled at build time.
# Build from the kit root so the shared runner library is in the build context:
#
#   docker build -f runners/minimax-h3/Dockerfile -t registry.example.com/ii-os/minimax-h3:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_MINIMAX_H3 to the pushed reference
# pinned by digest (registry.example.com/ii-os/minimax-h3@sha256:...). No model
# weights are baked in and nothing is installed at run time: the workflow
# mounts ${II_OS_MODEL_ROOT}/minimax-h3 read-only at /models and runs the
# container with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ARG COMFYUI_REVISION=e01fb4c56b7a88149d469b99cbbfe3223d715054
ARG SAGEATTENTION_REVISION=d1a57a546c3d395b1ffcbeecc66d81db76f3b4b5
# The GPU architectures SageAttention's kernels are compiled for. 8.6 (for
# example the GeForce RTX 30 series) is the verified configuration; add yours,
# such as "8.6;8.9" for an RTX 40-series card. SageAttention 2.2 supports 8.0,
# 8.6, 8.9, 9.0, 10.0, 12.0 and 12.1.
ARG SAGEATTENTION_CUDA_ARCH_LIST=8.6

# The pip-installed CUDA 13.0 toolkit (in the lock) provides nvcc for
# the SageAttention build and the CUDA runtime comfy-kitchen loads by name.
# PYTORCH_CUDA_ALLOC_CONF and CUDA_MODULE_LOADING keep fragmentation and
# start-up memory down; synchronous kernel launches are how the profile's
# timings were measured and keep a kernel fault attached to the node that
# caused it.
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/opt/venv/lib/python3.12/site-packages/nvidia/cu13 \
    PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/bin:/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:128 \
    CUDA_MODULE_LOADING=LAZY \
    CUDA_LAUNCH_BLOCKING=1

# ffmpeg probes reference clips, encodes the 720p delivery and extracts the
# poster. Triton compiles a small launcher at run time, so the image keeps a C
# compiler and the Python headers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates ffmpeg git libgl1 libglib2.0-0 python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Every Python package comes from this runner's lock files, pinned by version
# and sha256 and installed from wheels without dependency resolution: the
# installer (requirements-build.lock.txt) first, then everything the runner
# imports (requirements.lock.txt, generated from requirements.in).
COPY runners/minimax-h3/requirements-build.lock.txt runners/minimax-h3/requirements.lock.txt /opt/ii-os-runner/minimax-h3/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps --only-binary :all: -r /opt/ii-os-runner/minimax-h3/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --only-binary :all: -r /opt/ii-os-runner/minimax-h3/requirements.lock.txt

# ComfyUI at the commit the graph was verified against. Its requirements.txt
# is already satisfied by the lock; the check below fails the build if a
# revision bump adds one the lock lacks.
RUN git clone --filter=blob:none --no-checkout https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && git -C /opt/ComfyUI checkout --detach "${COMFYUI_REVISION}" \
    && test "$(git -C /opt/ComfyUI rev-parse HEAD)" = "${COMFYUI_REVISION}" \
    && rm -rf /opt/ComfyUI/.git \
    && python3 -c "import importlib.metadata as m, re; [m.version(re.split(r'[<>=~!;\[ ]', line.strip())[0]) for line in open('/opt/ComfyUI/requirements.txt') if line.strip() and not line.startswith('#')]"

# SageAttention 2.2.0 from its pinned commit, compiled against the locked torch
# for SAGEATTENTION_CUDA_ARCH_LIST (no GPU is needed at build time).
RUN git clone --filter=blob:none --no-checkout https://github.com/thu-ml/SageAttention.git /tmp/SageAttention \
    && git -C /tmp/SageAttention checkout --detach "${SAGEATTENTION_REVISION}" \
    && test "$(git -C /tmp/SageAttention rev-parse HEAD)" = "${SAGEATTENTION_REVISION}" \
    && test -x "${CUDA_HOME}/bin/nvcc" \
    && { test -e "${CUDA_HOME}/lib/libcudart.so" || ln -s libcudart.so.13 "${CUDA_HOME}/lib/libcudart.so"; } \
    && export TORCH_CUDA_ARCH_LIST="${SAGEATTENTION_CUDA_ARCH_LIST}" MAX_JOBS=4 EXT_PARALLEL=2 NVCC_APPEND_FLAGS="--threads 2" \
    && pip install --no-deps --no-build-isolation /tmp/SageAttention \
    && rm -rf /tmp/SageAttention

# The two vendored nodes the graph uses (exact low-memory patch, CAB sampler);
# ComfyUI loads no other custom node.
COPY runners/minimax-h3/comfy_nodes/ii_os_minimax_h3 /opt/ComfyUI/custom_nodes/ii_os_minimax_h3
COPY runners/common /opt/ii-os-runner/common
COPY runners/minimax-h3 /opt/ii-os-runner/minimax-h3

RUN pip check \
    && ffmpeg -hide_banner -version >/dev/null \
    && test "$(python3 -c 'import importlib.metadata as m; print(m.version("sageattention"))')" = 2.2.0 \
    && python3 /opt/ii-os-runner/minimax-h3/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/minimax-h3/entrypoint.py"]
CMD ["run", "--task", "text-to-video"]
