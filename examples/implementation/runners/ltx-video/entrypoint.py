#!/usr/bin/env python3
"""ltx-video runner: LTX-2.3 video generation through ComfyUI.

    python3 runners/ltx-video/entrypoint.py plan --task image-to-video --input-dir <work>/in
    docker run ... <image> run --task image-to-video

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
    "image-to-video": "tasks.image_to_video",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
