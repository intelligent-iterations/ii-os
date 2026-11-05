#!/usr/bin/env python3
"""Run one runner image against one claimed request, isolated.

The model container runs third-party model code, so it gets as little as
possible:

- no network (`--network none`); inputs were staged on the host by the claim;
- the runner's model folder `${II_OS_MODEL_ROOT}/<runner>/` read-only at
  `/models`, the request's `in/` read-only at `/work/in`, and only `out/`
  writable at `/work/out`;
- the runner user's uid/gid, no capabilities, no privilege escalation, a
  process limit, and a private `/tmp`;
- a digest-pinned image that must already be present (`--pull never`); `run`
  pulls it first, while the job still has network.

    python3 scripts/ii_os_run_container.py run --runner comfyui-image --gpu \
        --image "$II_OS_RUNNER_IMAGE" --model-root "$II_OS_MODEL_ROOT" \
        --work-dir "$WORK_DIR" -- run
    python3 scripts/ii_os_run_container.py remove --runner comfyui-image
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Mapping, Sequence

from ii_os_settings import PINNED_IMAGE

RUNNER = re.compile(r"^[a-z0-9][a-z0-9-]{1,40}$")
OPTION_ENV = re.compile(r"^II_OS_OPTION_[A-Z0-9_]{1,40}$")
CONTAINER_ENV = {
    # The container runs as the runner's uid, which has no passwd entry in the
    # image; libraries that ask for the user name read these instead.
    "USER": "ii-os-runner",
    "LOGNAME": "ii-os-runner",
    "HOME": "/tmp/home",
    "XDG_CACHE_HOME": "/tmp/cache",
    "HF_HUB_OFFLINE": "1",
    "HF_DATASETS_OFFLINE": "1",
    "TRANSFORMERS_OFFLINE": "1",
    "HF_HUB_DISABLE_TELEMETRY": "1",
    "DO_NOT_TRACK": "1",
    "II_OS_MODELS": "/models",
    "II_OS_INPUT": "/work/in",
    "II_OS_OUTPUT": "/work/out",
}


def container_name(runner: str, *, run_id: int, run_attempt: int) -> str:
    if not RUNNER.fullmatch(runner):
        raise ValueError("runner must be a lowercase runner folder name")
    return f"ii-os-{runner}-{run_id}-{run_attempt}"


def build_command(
    *,
    image: str,
    runner: str,
    model_root: Path | None,
    work_dir: Path,
    name: str,
    gpu: bool,
    uid: int,
    gid: int,
    args: Sequence[str],
    extra_env: Mapping[str, str] | None = None,
    shm_size: str = "8g",
    tmp_size: str = "32g",
    pids_limit: int = 4096,
) -> list[str]:
    if not PINNED_IMAGE.fullmatch(image):
        raise ValueError("the runner image must be pinned by digest (name@sha256:<64 hex>)")
    if not RUNNER.fullmatch(runner):
        raise ValueError("runner must be a lowercase runner folder name")
    mounts: list[str] = []
    if model_root is not None:
        folder = model_root / runner
        if folder.is_symlink() or not folder.is_dir():
            raise ValueError(f"model folder {folder} is missing")
        mounts.append(_mount(folder, "/models", read_only=True))
    for child, target, read_only in (("in", "/work/in", True), ("out", "/work/out", False)):
        path = work_dir / child
        if path.is_symlink() or not path.is_dir():
            raise ValueError(f"run directory {path} is missing")
        mounts.append(_mount(path, target, read_only=read_only))
    environment = dict(CONTAINER_ENV)
    for key, value in (extra_env or {}).items():
        if not OPTION_ENV.fullmatch(key) or "\n" in value:
            raise ValueError(f"{key} is not a runner option; container environment is limited to II_OS_OPTION_*")
        environment[key] = value
    command = [
        "docker", "run", "--rm", "--pull", "never",
        "--name", name,
        "--network", "none",
        "--user", f"{uid}:{gid}",
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--pids-limit", str(pids_limit),
        "--shm-size", shm_size,
        "--tmpfs", f"/tmp:rw,exec,nosuid,size={tmp_size}",
    ]
    if gpu:
        command += ["--gpus", "all"]
    for mount in mounts:
        command += ["--mount", mount]
    for key, value in environment.items():
        command += ["--env", f"{key}={value}"]
    return command + [image, *args]


def _mount(path: Path, target: str, *, read_only: bool) -> str:
    source = path.resolve()
    if "," in str(source) or "\n" in str(source):
        raise ValueError(f"{source} contains a comma or line break, which bind mount syntax cannot carry")
    return f"type=bind,source={source},target={target}" + (",readonly" if read_only else "")


def _ensure_image(image: str) -> None:
    present = subprocess.run(["docker", "image", "inspect", image], capture_output=True, check=False)
    if present.returncode != 0:
        subprocess.run(["docker", "pull", "--quiet", image], check=True)


def _options(env: Mapping[str, str]) -> dict[str, str]:
    return {key: value for key, value in env.items() if OPTION_ENV.fullmatch(key)}


def main(argv: Sequence[str], env: Mapping[str, str] | None = None) -> int:
    env = os.environ if env is None else env
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run")
    run.add_argument("--runner", required=True)
    run.add_argument("--image", required=True)
    run.add_argument("--model-root", type=Path, help="omit for runners that read no models")
    run.add_argument("--work-dir", type=Path, required=True)
    run.add_argument("--gpu", action="store_true")
    run.add_argument("--shm-size", default="8g")
    run.add_argument("args", nargs=argparse.REMAINDER)
    remove = sub.add_parser("remove")
    remove.add_argument("--runner", required=True)
    parsed = parser.parse_args(list(argv))
    name = container_name(parsed.runner, run_id=int(env["GITHUB_RUN_ID"]), run_attempt=int(env["GITHUB_RUN_ATTEMPT"]))
    if parsed.command == "remove":
        subprocess.run(["docker", "rm", "--force", name], capture_output=True, check=False)
        print(f"removed container {name} if it was still present")
        return 0
    args = parsed.args[1:] if parsed.args[:1] == ["--"] else parsed.args
    command = build_command(
        image=parsed.image,
        runner=parsed.runner,
        model_root=parsed.model_root,
        work_dir=parsed.work_dir,
        name=name,
        gpu=parsed.gpu,
        uid=os.getuid(),
        gid=os.getgid(),
        args=args,
        extra_env=_options(env),
        shm_size=parsed.shm_size,
    )
    _ensure_image(parsed.image)
    print(f"running {parsed.runner} in {name} with no network", flush=True)
    # nosemgrep: python.lang.security.audit.dangerous-subprocess-use-tainted-env-args.dangerous-subprocess-use-tainted-env-args -- Validated Docker options use separate argv elements with shell=False; task arguments follow the pinned image.
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"::error title=ii-os runner container::{error}")
        raise SystemExit(2) from None
