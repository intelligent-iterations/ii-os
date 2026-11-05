#!/usr/bin/env python3
"""seedvr2-video runner: SeedVR2 video upscaling through ComfyUI.

    python3 runners/seedvr2-video/entrypoint.py plan --task video-upscale --input-dir <work>/in
    docker run ... <image> run --task video-upscale

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
    "video-upscale": "tasks.video_upscale",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
