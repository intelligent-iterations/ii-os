#!/usr/bin/env python3
"""open-jev runner: typed text classification with the open JEV decision model.

    python3 runners/open-jev/entrypoint.py plan --task classify --input-dir <work>/in
    docker run ... <image> run --task classify

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
    "classify": "tasks.classify",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
