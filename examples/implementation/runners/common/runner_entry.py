"""The entrypoint every runner shares.

    entrypoint.py plan --task <task> --input-dir <work>/in --github-output "$GITHUB_OUTPUT"
        On the host, before any image is pulled: validate the claimed request
        and output the plan's `profile`, the models.json profile the
        model-folder check uses. Nothing else from the request is logged.

    entrypoint.py run --task <task>
        In the container (defaults: /work/in, /work/out, /models): validate
        again, generate, and write out/result.json. A refusal the task can
        name (RequestError with a code) is written to out/failure.json.

A task is a module with:

    plan(request: Request) -> dict              # must include "profile"
    run(plan, request, context) -> (artifacts, metadata)
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import importlib
import json
from pathlib import Path
import sys
import traceback
from typing import Mapping, Sequence

import runner_io


@dataclass(frozen=True)
class RunContext:
    models_dir: Path
    output_dir: Path
    scratch_dir: Path
    options: dict[str, str]


def main(argv: Sequence[str], tasks: Mapping[str, str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("plan", "run"))
    parser.add_argument("--task", required=True, choices=sorted(tasks))
    parser.add_argument("--input-dir", type=Path, default=Path("/work/in"))
    parser.add_argument("--output-dir", type=Path, default=Path("/work/out"))
    parser.add_argument("--models-dir", type=Path, default=Path("/models"))
    parser.add_argument("--scratch-dir", type=Path, default=Path("/tmp/ii-os-scratch"))
    parser.add_argument("--github-output", default="")
    args = parser.parse_args(list(argv))
    task = importlib.import_module(tasks[args.task])
    try:
        request = runner_io.Request.load(args.input_dir)
        plan = task.plan(request)
        profile = plan.get("profile")
        if not isinstance(profile, str) or not profile:
            raise RuntimeError(f"task {args.task} planned no model profile")
        if args.command == "plan":
            # Only the profile is logged: plans carry the user's creative text,
            # which stays out of GitHub run logs.
            print(json.dumps({"task": args.task, "profile": profile}))
            runner_io.write_github_output(args.github_output, {"profile": profile})
            return 0
        args.scratch_dir.mkdir(parents=True, exist_ok=True)
        Path.home().mkdir(parents=True, exist_ok=True)
        context = RunContext(args.models_dir, args.output_dir, args.scratch_dir, runner_io.options())
        artifacts, metadata = task.run(plan, request, context)
        runner_io.write_result(args.output_dir, artifacts, metadata)
        print(f"{args.task}: wrote {', '.join(item.file for item in artifacts)}")
        return 0
    except runner_io.RequestError as error:
        print(f"::error title=ii-os request refused::{error}")
        if args.command == "run" and error.code:
            runner_io.write_failure(args.output_dir, error.code)
        return 2
    except Exception:  # noqa: BLE001 - the trace is the diagnostic for a runner failure
        traceback.print_exc(file=sys.stderr)
        return 1
