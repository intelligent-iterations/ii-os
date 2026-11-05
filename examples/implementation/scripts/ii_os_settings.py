#!/usr/bin/env python3
"""Fail a workflow early, by name, when a kit setting is missing or unsafe.

Every pointer the kit uses (connector, token, model folder, runner image) is a
repository variable or secret. A job must stop in its first step with the name
of the setting to fix; it never falls back to a default host, folder or image.

    python3 scripts/ii_os_settings.py check --connector --model-root \
        --runner-image II_OS_RUNNER_IMAGE_COMFYUI_IMAGE
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys
from typing import Mapping, Sequence

# A registry reference that names one immutable image: [host[:port]/]path[:tag]@sha256:<64 hex>.
PINNED_IMAGE = re.compile(
    r"^(?:[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::[0-9]{1,5})?/)?"
    r"[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*(?:/[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*)*"
    r"(?::[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?@sha256:[0-9a-f]{64}$"
)
RUNNER_IMAGE_VARIABLE = re.compile(r"^II_OS_RUNNER_IMAGE_[A-Z0-9_]+$")


class SettingError(RuntimeError):
    """A kit setting is missing or invalid. The message names it."""


def require(env: Mapping[str, str], name: str, purpose: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise SettingError(f"Setting {name} is missing. Set it to {purpose}.")
    return value


def connector(env: Mapping[str, str]) -> tuple[str, str]:
    url = require(env, "II_OS_CONNECTOR_URL", "your ii-os API base URL (a repository variable)")
    if not url.startswith("https://") or "?" in url:
        raise SettingError("Setting II_OS_CONNECTOR_URL must be an https URL with no query string.")
    token = require(env, "II_OS_TOKEN", "the workflow token ii-os issued for this repository (a repository secret)")
    return url, token


def model_root(env: Mapping[str, str]) -> Path:
    raw = require(env, "II_OS_MODEL_ROOT", "the absolute folder on the runner host that holds one folder per runner")
    path = Path(raw)
    if not path.is_absolute() or path == Path(path.anchor):
        raise SettingError("Setting II_OS_MODEL_ROOT must be an absolute folder other than the filesystem root.")
    if not path.is_dir():
        raise SettingError(f"Setting II_OS_MODEL_ROOT points at {raw}, which is not a folder on this runner.")
    return path


def runner_image(env: Mapping[str, str], variable: str) -> str:
    if not RUNNER_IMAGE_VARIABLE.fullmatch(variable):
        raise SettingError(f"{variable} is not a runner image setting name.")
    value = require(env, variable, "the digest-pinned image you built from runners/<runner>/Dockerfile")
    if not PINNED_IMAGE.fullmatch(value):
        raise SettingError(
            f"Setting {variable} must name one immutable image, for example "
            "registry.example.com/ii-os/comfyui-image@sha256:<64 hex characters>."
        )
    return value


def check(env: Mapping[str, str], *, want_connector: bool, want_model_root: bool, images: Sequence[str]) -> None:
    if want_connector:
        connector(env)
    if want_model_root:
        model_root(env)
    for variable in images:
        runner_image(env, variable)


def main(argv: Sequence[str], env: Mapping[str, str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    child = sub.add_parser("check")
    child.add_argument("--connector", action="store_true", help="require II_OS_CONNECTOR_URL and II_OS_TOKEN")
    child.add_argument("--model-root", action="store_true", help="require II_OS_MODEL_ROOT")
    child.add_argument("--runner-image", action="append", default=[], help="require this II_OS_RUNNER_IMAGE_* variable")
    args = parser.parse_args(list(argv))
    check(
        os.environ if env is None else env,
        want_connector=args.connector,
        want_model_root=args.model_root,
        images=args.runner_image,
    )
    print("ii-os kit settings: ok")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except SettingError as error:
        print(f"::error title=ii-os setting::{error}")
        raise SystemExit(2) from None
