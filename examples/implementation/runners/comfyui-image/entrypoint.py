#!/usr/bin/env python3
"""comfyui-image runner: image generation and editing through ComfyUI.

    python3 runners/comfyui-image/entrypoint.py plan --task text-to-image --input-dir <work>/in
    docker run ... <image> run --task text-to-image

See runners/common/runner_entry.py for the plan/run contract.
"""

from __future__ import annotations

from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
for path in (HERE, HERE.parent / "common"):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

import runner_entry  # noqa: E402

TASKS = {
    "text-to-image": "tasks.text_to_image",
    "z-image-edit": "tasks.z_image_edit",
    "qwen-image-edit": "tasks.qwen_image_edit",
    "flux2-klein-edit": "tasks.flux2_klein_edit",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
