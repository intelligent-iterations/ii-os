#!/usr/bin/env python3
"""acestep-song runner: songs with ACE-Step 1.5.

    python3 runners/acestep-song/entrypoint.py plan --task text-to-song --input-dir <work>/in
    docker run ... <image> run --task text-to-song

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
    "text-to-song": "tasks.text_to_song",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
