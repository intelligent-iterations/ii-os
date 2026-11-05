#!/usr/bin/env python3
"""media-render runner: CPU video-editor exports through ii-os's own renderer.

    python3 runners/media-render/entrypoint.py plan --task editor-render --input-dir <work>/in
    docker run ... <image> run --task editor-render

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
    "editor-render": "tasks.editor_render",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
