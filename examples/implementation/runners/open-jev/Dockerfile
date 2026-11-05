# syntax=docker/dockerfile:1
#
# open-jev runner: the vendored open JEV decision engine (Apache-2.0) on
# PyTorch with CUDA 13.0. Build from the kit root so the shared runner library
# is in the build context:
#
#   docker build -f runners/open-jev/Dockerfile -t registry.example.com/ii-os/open-jev:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_OPEN_JEV to the pushed reference pinned
# by digest (registry.example.com/ii-os/open-jev@sha256:...). No model weights
# are baked in: the workflow mounts ${II_OS_MODEL_ROOT}/open-jev read-only at
# /models and runs the container with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    TOKENIZERS_PARALLELISM=false \
    PATH=/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Triton, which runs the model's linear-attention kernels, compiles a small
# launcher at run time, so the image keeps a C compiler and the Python headers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Every Python package comes from this runner's lock files, pinned by version
# and sha256 and installed without dependency resolution: the installer
# (requirements-build.lock.txt) first, then everything the runner imports
# (requirements.lock.txt). See README.md to recompile them. The set is exactly
# the one the engine was validated with (requirements.in); `pip check` below
# proves it is complete and consistent. torch 2.13.0 on PyPI is the CUDA 13.0
# build; its CUDA libraries are the pinned nvidia wheels.
COPY runners/open-jev/requirements-build.lock.txt runners/open-jev/requirements.lock.txt /opt/ii-os-runner/open-jev/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps -r /opt/ii-os-runner/open-jev/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --no-build-isolation \
      -r /opt/ii-os-runner/open-jev/requirements.lock.txt

COPY runners/common /opt/ii-os-runner/common
COPY runners/open-jev /opt/ii-os-runner/open-jev

RUN pip check \
    && python3 /opt/ii-os-runner/open-jev/entrypoint.py --help >/dev/null \
    && python3 -c "import torch, transformers, peft, accelerate, fla, safetensors; print(torch.__version__, torch.version.cuda, transformers.__version__, peft.__version__)"

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/open-jev/entrypoint.py"]
CMD ["run", "--task", "classify"]
