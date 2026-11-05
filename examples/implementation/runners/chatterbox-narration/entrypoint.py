#!/usr/bin/env python3
"""chatterbox-narration runner: text-to-speech with Chatterbox Turbo.

    python3 runners/chatterbox-narration/entrypoint.py plan --task text-to-speech --input-dir <work>/in
    docker run ... <image> run --task text-to-speech

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
    "text-to-speech": "tasks.text_to_speech",
}

if __name__ == "__main__":
    raise SystemExit(runner_entry.main(sys.argv[1:], TASKS))
