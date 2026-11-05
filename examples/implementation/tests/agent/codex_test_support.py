"""Shared fixtures for the Connect Codex unit tests (stdlib only).

Every test directory is created by the test run, carries a disposable
ownership marker, and is removed only after that marker is re-proven.
"""

from __future__ import annotations

import contextlib
import http.server
import json
import shutil
import sys
import tempfile
import threading
import uuid
from pathlib import Path
from typing import Callable, Iterator


KIT_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = KIT_ROOT / "scripts" / "agent"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

CONNECTOR = "https://ii-os.example.com/api"
REPOSITORY = "acme-co/example-app"
SESSION = "11111111-1111-4111-8111-111111111111"


@contextlib.contextmanager
def owned_directory() -> Iterator[Path]:
    path = Path(tempfile.mkdtemp(prefix="ii-os-codex-test-")).resolve(strict=True)
    owner = uuid.uuid4().hex
    marker = path / ".ii-os-disposable-owner"
    marker.write_text(owner)
    try:
        yield path
    finally:
        if path.is_symlink() or marker.is_symlink() or marker.read_text() != owner:
            raise RuntimeError("disposable test state ownership changed")
        shutil.rmtree(path)


class FakeServer:
    """A loopback HTTP server whose responses come from ``respond``.

    ``respond(method, path, headers, body)`` returns ``(status, headers, body)``.
    Every request is recorded in ``requests``.
    """

    def __init__(self, respond: Callable[..., tuple[int, dict[str, str], bytes]]) -> None:
        self.requests: list[dict] = []
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def _handle(self) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(length) if length else b""
                owner.requests.append({"method": self.command, "path": self.path,
                                       "headers": dict(self.headers), "body": body})
                status, headers, payload = respond(self.command, self.path, dict(self.headers), body)
                self.send_response(status)
                for name, value in headers.items():
                    self.send_header(name, value)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            do_GET = do_POST = _handle

            def log_message(self, *args: object) -> None:
                pass

        self._server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.base = f"http://127.0.0.1:{self._server.server_address[1]}"
        self._thread = threading.Thread(target=self._server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)

    def __enter__(self) -> "FakeServer":
        self._thread.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(5)


def json_response(value: object, status: int = 200) -> tuple[int, dict[str, str], bytes]:
    return status, {"Content-Type": "application/json"}, json.dumps(value).encode()
