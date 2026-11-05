"""Shared helpers for the workflow kit's offline unit tests.

The kit's scripts and runner adapters are loaded by file path so the tests run
from any checkout layout (the kit at a repository root, or nested under
`examples/implementation/`) and runner folders may keep their hyphenated names.
"""

from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from types import ModuleType
from typing import Any
import urllib.error

KIT_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = KIT_ROOT / "scripts"
RUNNERS = KIT_ROOT / "runners"

for _path in (SCRIPTS, RUNNERS / "common"):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))


def load(relative_path: str, name: str | None = None) -> ModuleType:
    """Import one kit module from its path relative to the kit root."""
    path = KIT_ROOT / relative_path
    module_name = name or "kit_" + relative_path.replace("/", "_").replace("-", "_").removesuffix(".py")
    if module_name in sys.modules:
        return sys.modules[module_name]
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    directory = str(path.parent)
    added = directory not in sys.path
    if added:
        sys.path.insert(0, directory)
    try:
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
    except BaseException:
        sys.modules.pop(module_name, None)
        raise
    finally:
        if added:
            sys.path.remove(directory)
    return module


class FakeResponse(io.BytesIO):
    """The subset of an `http.client.HTTPResponse` the kit reads."""

    def __init__(self, status: int, body: bytes | str | dict[str, Any] = b"", headers: dict[str, str] | None = None):
        if isinstance(body, dict):
            body = json.dumps(body)
        if isinstance(body, str):
            body = body.encode("utf-8")
        super().__init__(body)
        self.status = status
        self.headers = {key.lower(): value for key, value in (headers or {}).items()}

    def getheader(self, name: str, default: str | None = None) -> str | None:
        return self.headers.get(name.lower(), default)

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


class RecordingOpener:
    """Replays queued responses and records every request the code made."""

    def __init__(self, responses: list[FakeResponse | Exception]):
        self.responses = list(responses)
        self.requests: list[dict[str, Any]] = []

    def __call__(self, request: Any, timeout: float | None = None) -> FakeResponse:
        data = request.data
        if hasattr(data, "read"):
            data = data.read()
        self.requests.append(
            {
                "method": request.get_method(),
                "url": request.full_url,
                "headers": {key.lower(): value for key, value in request.header_items()},
                "body": data,
                "timeout": timeout,
            }
        )
        if not self.responses:
            raise AssertionError(f"unexpected request {request.get_method()} {request.full_url}")
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        if response.status >= 400:
            raise urllib.error.HTTPError(
                request.full_url, response.status, "error", response.headers, response
            )
        return response


def json_body(record: dict[str, Any]) -> Any:
    return json.loads(record["body"].decode("utf-8"))


class TempDir:
    """A disposable directory owned by one test."""

    def __init__(self) -> None:
        self._handle = tempfile.TemporaryDirectory(prefix="ii-os-kit-test-")
        self.path = Path(self._handle.name).resolve()

    def cleanup(self) -> None:
        self._handle.cleanup()
