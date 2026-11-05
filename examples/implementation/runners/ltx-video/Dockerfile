# syntax=docker/dockerfile:1
#
# ltx-video runner. Build from the kit root so the shared runner library is
# in the build context:
#
#   docker build -f runners/ltx-video/Dockerfile -t registry.example.com/ii-os/ltx-video:2026-11 .
#
# Push it, then set II_OS_RUNNER_IMAGE_LTX_VIDEO to the pushed reference
# pinned by digest (registry.example.com/ii-os/ltx-video@sha256:...).
# No model weights are baked in: the workflow mounts
# ${II_OS_MODEL_ROOT}/ltx-video read-only at /models and runs the container
# with no network.
FROM nvidia/cuda:13.0.3-base-ubuntu24.04@sha256:7c7413a56200486f71f181cad9310f6fd31b6bb21816ade15fc9c1e1e927a5c1

ARG COMFYUI_REVISION=5f0c4e18cb7e98f0e7c46c2c7ce928d641351e67
# The custom node packs the LTX-2.3 graph was verified alongside. At this
# ComfyUI commit the graph itself uses core nodes only (see README.md).
ARG LTXVIDEO_NODES_REVISION=aceeae9635f6d493f2893ba3c411a1c36031788a
ARG KJNODES_REVISION=e27a505b3ba6ce42687fe00500deda103d9d6071
ARG VIDEOHELPERSUITE_REVISION=4ee72c065db22c9d96c2427954dc69e7b908444b

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/opt/venv/lib/python3.12/site-packages/nvidia/cu13 \
    LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/bin:/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ffmpeg extracts the poster frame from the finished video.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates ffmpeg git libgl1 libglib2.0-0 python3 python3-dev python3-venv tini \
    && rm -rf /var/lib/apt/lists/*

# Every Python package comes from this runner's lock files, pinned by version
# and sha256 and installed without dependency resolution: the installer
# (requirements-build.lock.txt) first, then everything the runner imports
# (requirements.lock.txt). See README.md to recompile them. The CUDA 13.0
# packages and toolkit come from PyPI and are also hash-pinned in the lock.
COPY runners/ltx-video/requirements-build.lock.txt runners/ltx-video/requirements.lock.txt /opt/ii-os-runner/ltx-video/
RUN python3 -m venv /opt/venv \
    && pip install --require-hashes --no-deps -r /opt/ii-os-runner/ltx-video/requirements-build.lock.txt \
    && pip install --require-hashes --no-deps --no-build-isolation \
      --index-url https://pypi.org/simple \
      -r /opt/ii-os-runner/ltx-video/requirements.lock.txt

# ComfyUI's requirements and the three node packs' requirements at these
# revisions are part of requirements.in, which also holds kornia at 0.8.2.
RUN git clone --filter=blob:none --no-checkout https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && git -C /opt/ComfyUI checkout --detach "${COMFYUI_REVISION}" \
    && test "$(git -C /opt/ComfyUI rev-parse HEAD)" = "${COMFYUI_REVISION}" \
    && rm -rf /opt/ComfyUI/.git

RUN set -eu; \
    for node in \
      "ComfyUI-LTXVideo https://github.com/Lightricks/ComfyUI-LTXVideo.git ${LTXVIDEO_NODES_REVISION}" \
      "ComfyUI-KJNodes https://github.com/kijai/ComfyUI-KJNodes.git ${KJNODES_REVISION}" \
      "ComfyUI-VideoHelperSuite https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ${VIDEOHELPERSUITE_REVISION}"; \
    do \
      set -- ${node}; \
      target="/opt/ComfyUI/custom_nodes/$1"; \
      git clone --filter=blob:none --no-checkout "$2" "${target}"; \
      git -C "${target}" checkout --detach "$3"; \
      test "$(git -C "${target}" rev-parse HEAD)" = "$3"; \
      rm -rf "${target}/.git"; \
    done

COPY runners/common /opt/ii-os-runner/common
COPY runners/ltx-video /opt/ii-os-runner/ltx-video

RUN pip check \
    && ffmpeg -hide_banner -version >/dev/null \
    && python3 /opt/ii-os-runner/ltx-video/entrypoint.py --help >/dev/null

# The workflow runs the container as the runner's own uid:gid; this default
# only applies when someone runs the image by hand.
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/ltx-video/entrypoint.py"]
CMD ["run", "--task", "image-to-video"]
