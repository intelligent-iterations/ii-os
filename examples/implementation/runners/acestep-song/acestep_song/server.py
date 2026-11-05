"""ACE-Step 1.5's own REST API server, run on loopback inside the runner container.

The container has no network and a read-only model folder, while ACE-Step
expects to write into its checkpoints folder (it syncs its model code there)
and under its source tree (a result cache and temporary audio). The image
therefore replaces `<ACE-Step>/checkpoints` and `<ACE-Step>/.cache` with
symlinks into the container's private /tmp, and before each run this module:

- lays out that checkpoints folder: every model folder is linked to
  /models/<folder>; the DiT folder is a real folder whose weights are linked
  and whose Python model code is copied from the pinned ACE-Step source, so
  ACE-Step finds its own code and never writes to /models;
- starts `python -m acestep.api_server` on 127.0.0.1 with a fresh API key in
  its environment (never on the command line) and every download path off;
- talks to it over HTTP, then stops the whole process group.

The server log can echo the prompt, lyrics and text the planner LM derives
from them, so it stays in /tmp. On failure only diagnostic lines are printed,
with the request's text redacted. Standard library only.
"""

from __future__ import annotations

from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import subprocess
import time
from typing import Any, Callable, Iterator, Mapping, Sequence
import urllib.error
import urllib.parse
import urllib.request

ACE_ROOT = Path("/opt/ACE-Step-1.5")
# The ACE-Step model-code folder (acestep/models/<variant>) for each DiT this runner loads.
DIT_CODE = {"acestep-v15-xl-turbo": "xl_turbo"}
HOST = "127.0.0.1"
REQUEST_TIMEOUT_SECONDS = 60
DOWNLOAD_TIMEOUT_SECONDS = 300
POLL_SECONDS = 5
EXCERPT_LINES = 60
EXCERPT_WIDTH = 300
DIAGNOSTIC = re.compile(
    r"Traceback \(most recent call last\)|^\s+File \"|^[A-Za-z_][\w.]*(Error|Exception)\b"
    r"|\|\s*(ERROR|CRITICAL)\s*\||\bERROR:|CUDA out of memory"
)

Opener = Callable[..., Any]


def writable_target(link: Path) -> Path:
    """Where an image symlink points; it must be inside the container's private /tmp."""
    if not link.is_symlink():
        raise RuntimeError(f"{link} must be a symlink into /tmp; rebuild the image from runners/acestep-song/Dockerfile")
    target = Path(os.readlink(link))
    if not target.is_absolute() or target.parts[:2] != ("/", "tmp"):
        raise RuntimeError(f"{link} must point into /tmp")
    return target


def link_checkpoints(models_dir: Path, target: Path, *, dit: str, code_dir: Path) -> None:
    """Lay out ACE-Step's checkpoints folder in scratch over the read-only model folder."""
    if not (models_dir / dit).is_dir():
        raise RuntimeError(f"the model folder has no {dit} folder")
    code = sorted(path for path in code_dir.glob("*.py") if path.name != "__init__.py") if code_dir.is_dir() else []
    if not code:
        raise RuntimeError(f"the pinned ACE-Step model code is missing from {code_dir}")
    target.mkdir(parents=True, exist_ok=False)
    for entry in sorted(models_dir.iterdir()):
        if entry.name.startswith("."):
            continue
        link = target / entry.name
        if entry.name != dit:
            link.symlink_to(entry, target_is_directory=entry.is_dir())
            continue
        link.mkdir()
        for item in sorted(entry.iterdir()):
            if item.suffix != ".py" and not item.name.startswith("."):
                (link / item.name).symlink_to(item)
        for path in code:
            shutil.copyfile(path, link / path.name)


def server_environment(
    base: Mapping[str, str], *, token: str, port: int, dit: str, lm: str | None, checkpoints: Path, tmp_dir: Path
) -> dict[str, str]:
    env = {key: value for key, value in base.items() if not key.startswith("ACESTEP_")}
    env.update(
        {
            "ACESTEP_API_KEY": token,
            "ACESTEP_API_HOST": HOST,
            "ACESTEP_API_PORT": str(port),
            "ACESTEP_CHECKPOINTS_DIR": str(checkpoints),
            "ACESTEP_TMPDIR": str(tmp_dir),
            "ACESTEP_CONFIG_PATH": dit,
            "ACESTEP_DEVICE": "cuda",
            "ACESTEP_INIT_LLM": "true" if lm else "false",
            "ACESTEP_LM_MODEL_PATH": lm or "",
            "ACESTEP_LM_BACKEND": "vllm",
            "ACESTEP_NO_INIT": "false",
            "ACESTEP_OFFLOAD_TO_CPU": "false",
            "ACESTEP_LM_OFFLOAD_TO_CPU": "false",
            "ACESTEP_OFFLOAD_DIT_TO_CPU": "false",
            "ACESTEP_DOWNLOAD_SOURCE": "huggingface",
            "GRADIO_ANALYTICS_ENABLED": "False",
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
        }
    )
    return env


def server_command(python: Path, port: int, *, lm: str | None) -> list[str]:
    command = [str(python), "-m", "acestep.api_server", "--host", HOST, "--port", str(port)]
    if lm:
        command += ["--init-llm", "--lm-model-path", lm]
    return command


def log_excerpt(text: str, redact: Sequence[str]) -> list[str]:
    lines = [line for line in text.splitlines() if DIAGNOSTIC.search(line)]
    return [redact_text(line, redact)[:EXCERPT_WIDTH] for line in lines[-EXCERPT_LINES:]]


def redact_text(text: str, values: Sequence[str]) -> str:
    for value in sorted({value for value in values if value}, key=len, reverse=True):
        text = text.replace(value, "[redacted]")
    return text


class AceStepClient:
    """HTTP calls to one loopback ACE-Step API server."""

    def __init__(
        self,
        base_url: str,
        token: str,
        *,
        opener: Opener = urllib.request.urlopen,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
        redact: Sequence[str] = (),
    ):
        self.base_url = base_url
        self._token = token
        self._open = opener
        self._sleep = sleep
        self._clock = clock
        self._redact = tuple(redact)

    @property
    def token(self) -> str:
        """The API key every request carries (release bodies repeat it as ai_token)."""
        return self._token

    def _json(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        data = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(f"{self.base_url}{path}", data=data, method=method)
        request.add_header("Accept", "application/json")
        request.add_header("Authorization", f"Bearer {self._token}")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with self._open(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"ACE-Step API {path} returned HTTP {error.code}") from None

    def wait_until_ready(self, *, dit: str, lm: str | None, timeout: float, alive: Callable[[], bool]) -> None:
        deadline = self._clock() + timeout
        while self._clock() < deadline:
            if not alive():
                raise RuntimeError("the ACE-Step API server exited during startup")
            try:
                data = (self._json("GET", "/health") or {}).get("data") or {}
            except (OSError, ValueError, RuntimeError):
                data = {}
            if data.get("models_initialized") and (data.get("llm_initialized") or not lm):
                if data.get("loaded_model") != dit:
                    raise RuntimeError("ACE-Step loaded an unexpected DiT model")
                if lm and data.get("loaded_lm_model") != lm:
                    raise RuntimeError("ACE-Step loaded an unexpected LM model")
                return
            self._sleep(POLL_SECONDS)
        raise TimeoutError("ACE-Step models did not finish loading before the startup deadline")

    def release(self, payload: dict[str, Any]) -> str:
        task_id = str(((self._json("POST", "/release_task", payload) or {}).get("data") or {}).get("task_id") or "")
        if not task_id:
            raise RuntimeError("ACE-Step did not return a task id")
        return task_id

    def wait_for_result(self, task_id: str, *, timeout: float) -> str:
        deadline = self._clock() + timeout
        while self._clock() < deadline:
            rows = (self._json("POST", "/query_result", {"ai_token": self._token, "task_id_list": [task_id]}) or {}).get("data") or []
            row = rows[0] if rows and isinstance(rows[0], dict) else {}
            status = int(row.get("status") or 0)
            if status == 1:
                results = json.loads(row.get("result") or "[]")
                audio = results[0].get("file", "") if results and isinstance(results[0], dict) else ""
                if not audio:
                    raise RuntimeError("ACE-Step finished without an audio file")
                return str(audio)
            if status == 2:
                raise RuntimeError(f"ACE-Step generation failed: {self.failure_detail(row)}")
            self._sleep(POLL_SECONDS)
        raise TimeoutError("ACE-Step generation did not finish before its deadline")

    def failure_detail(self, row: dict[str, Any]) -> str:
        """Only the error fields of a failed task, redacted; never the echoed request."""
        details = [str(row[key]) for key in ("error", "message", "progress_text") if row.get(key)]
        try:
            nested = json.loads(row.get("result") or "[]")
        except (TypeError, json.JSONDecodeError):
            nested = []
        for item in nested if isinstance(nested, list) else []:
            if isinstance(item, dict):
                details += [f"{key}={item[key]}" for key in ("stage", "error", "message") if item.get(key) not in (None, "")]
        return redact_text("; ".join(details) or "no detail", self._redact)[:EXCERPT_WIDTH * 2]

    def download(self, audio_url: str, destination: Path) -> None:
        url = urllib.parse.urljoin(f"{self.base_url}/", audio_url)
        if not url.startswith(f"{self.base_url}/"):
            raise RuntimeError("ACE-Step named an audio file outside its loopback server")
        request = urllib.request.Request(url, method="GET")
        request.add_header("Authorization", f"Bearer {self._token}")
        try:
            with self._open(request, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response, destination.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"ACE-Step audio download returned HTTP {error.code}") from None
        if destination.stat().st_size == 0:
            raise RuntimeError("ACE-Step returned an empty audio file")


@contextmanager
def running(
    *, models_dir: Path, scratch: Path, dit: str, lm: str | None, redact: Sequence[str], ace_root: Path = ACE_ROOT
) -> Iterator[tuple[AceStepClient, Callable[[], bool]]]:
    """Start the API server for one profile; yield (client, alive) and always stop it."""
    checkpoints = writable_target(ace_root / "checkpoints")
    writable_target(ace_root / ".cache").mkdir(parents=True, exist_ok=True)
    link_checkpoints(models_dir, checkpoints, dit=dit, code_dir=ace_root / "acestep" / "models" / DIT_CODE[dit])
    tmp_dir = scratch / "tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(32)
    port = _free_port()
    log_path = scratch / "acestep-api.log"
    env = server_environment(os.environ, token=token, port=port, dit=dit, lm=lm, checkpoints=checkpoints, tmp_dir=tmp_dir)
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            server_command(ace_root / ".venv" / "bin" / "python", port, lm=lm),
            cwd=ace_root, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        failed = True
        try:
            yield AceStepClient(f"http://{HOST}:{port}", token, redact=redact), lambda: process.poll() is None
            failed = False
        finally:
            _stop(process)
            if failed:
                _print_excerpt(log_path, redact)


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind((HOST, 0))
        return int(sock.getsockname()[1])


def _stop(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=10)


def _print_excerpt(log_path: Path, redact: Sequence[str]) -> None:
    lines = log_excerpt(log_path.read_text(encoding="utf-8", errors="replace"), redact) if log_path.is_file() else []
    if lines:
        print("ACE-Step server diagnostics (request text redacted):", flush=True)
        for line in lines:
            print(line, flush=True)
