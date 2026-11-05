# syntax=docker/dockerfile:1
#
# comfyui-image runner. Build from the kit root so the shared runner library
# is in the build context:
#
#   docker build -f runners/comfyui-image/Dockerfile -t registry.example.com/ii-os/comfyui-image:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_COMFYUI_IMAGE to the pushed reference
# pinned by digest (registry.example.com/ii-os/comfyui-image@sha256:...).
# No model weights are baked in: the workflow mounts
# ${II_OS_MODEL_ROOT}/comfyui-image read-only at /models and runs the
# container with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ARG COMFYUI_REVISION=5f0c4e18cb7e98f0e7c46c2c7ce928d641351e67

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/opt/venv/lib/python3.12/site-packages/nvidia/cu13 \
    LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/bin:/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates git libgl1 libglib2.0-0 python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Every Python package comes from this runner's lock files, pinned by version
# and sha256 and installed without dependency resolution: the installer
# (requirements-build.lock.txt) first, then everything the runner imports
# (requirements.lock.txt). See README.md to recompile them. The CUDA 13.0
# packages and toolkit come from PyPI and are also hash-pinned in the lock.
COPY runners/comfyui-image/requirements-build.lock.txt runners/comfyui-image/requirements.lock.txt /opt/ii-os-runner/comfyui-image/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps -r /opt/ii-os-runner/comfyui-image/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --no-build-isolation \
      --index-url https://pypi.org/simple \
      -r /opt/ii-os-runner/comfyui-image/requirements.lock.txt

# ComfyUI's own requirements at this revision are part of requirements.in.
RUN git clone --filter=blob:none --no-checkout https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && git -C /opt/ComfyUI checkout --detach "${COMFYUI_REVISION}" \
    && test "$(git -C /opt/ComfyUI rev-parse HEAD)" = "${COMFYUI_REVISION}" \
    && rm -rf /opt/ComfyUI/.git

COPY runners/common /opt/ii-os-runner/common
COPY runners/comfyui-image /opt/ii-os-runner/comfyui-image

# The edit tasks draw and composite masks with Pillow, and the Z-Image edit
# graph's Canny node needs kornia; both come from ComfyUI's requirements.
RUN pip check \
    && python3 -c "import PIL, kornia" \
    && python3 /opt/ii-os-runner/comfyui-image/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/comfyui-image/entrypoint.py"]
CMD ["run", "--task", "text-to-image"]
