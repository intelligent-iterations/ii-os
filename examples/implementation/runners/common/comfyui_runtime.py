"""Run one ComfyUI API graph headlessly inside a runner container.

The container has no network. ComfyUI listens on loopback only, reads models
from the read-only `/models` mount through an `extra_model_paths.yaml` this
module writes (nothing is copied or symlinked into the image), and keeps its
input, output, temp and user folders under a run-scoped scratch folder.

Standard library only; the graphs themselves are plain dicts each task builds.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Any, Iterable, Mapping
import urllib.error
import urllib.parse
import urllib.request
import uuid

COMFY_ROOT = Path(os.environ.get("II_OS_COMFYUI_ROOT", "/opt/ComfyUI"))
OUTPUT_KEYS = ("images", "gifs", "videos", "audio")


def extra_model_paths(models_dir: Path) -> str:
    """Map every top-level folder of the model mount to a ComfyUI model folder name."""
    folders = sorted(child.name for child in models_dir.iterdir() if child.is_dir() and not child.name.startswith("."))
    lines = ["ii_os_models:", f"  base_path: {json.dumps(str(models_dir))}"]
    lines += [f"  {name}: {json.dumps(name + '/')}" for name in folders]
    return "\n".join(lines) + "\n"


def describe_failure(value: Any) -> str:
    """A ComfyUI error, reduced to what identifies it.

    ComfyUI's error payloads echo node inputs (`current_inputs`, the
    `received_value` and `details` of a validation error), which can hold the
    request's prompt. Only node ids, types, error types and messages survive,
    so a failure can be diagnosed from the job log without leaking the request.
    """
    summary: dict[str, Any] = {}
    if not isinstance(value, dict):
        return json.dumps({"error": "unreadable ComfyUI response"})
    if isinstance(value.get("status_str"), str):
        summary["status"] = value["status_str"]
    errors = []
    for message in value.get("messages", []) or []:
        if isinstance(message, list) and len(message) == 2 and message[0] in {"execution_error", "execution_interrupted"}:
            detail = message[1] if isinstance(message[1], dict) else {}
            errors.append(
                {
                    "event": message[0],
                    "node_id": str(detail.get("node_id", "")),
                    "node_type": str(detail.get("node_type", "")),
                    "exception_type": str(detail.get("exception_type", "")),
                    "exception_message": str(detail.get("exception_message", ""))[:500],
                }
            )
    if errors:
        summary["errors"] = errors
    error = value.get("error")
    if isinstance(error, dict):
        summary["error"] = {"type": str(error.get("type", "")), "message": str(error.get("message", ""))[:500]}
    node_errors = value.get("node_errors")
    if isinstance(node_errors, dict):
        summary["node_errors"] = {
            str(node): {
                "class_type": str(item.get("class_type", "")) if isinstance(item, dict) else "",
                "errors": [
                    {
                        "type": str(entry.get("type", "")),
                        "message": str(entry.get("message", ""))[:300],
                        "input_name": str((entry.get("extra_info") or {}).get("input_name", "")),
                    }
                    for entry in (item.get("errors", []) if isinstance(item, dict) else [])
                    if isinstance(entry, dict)
                ],
            }
            for node, item in node_errors.items()
        }
    return json.dumps(summary, sort_keys=True)


def required_nodes(graph: Mapping[str, Any]) -> set[str]:
    return {str(node["class_type"]) for node in graph.values() if isinstance(node, dict) and "class_type" in node}


def output_files(history_item: Mapping[str, Any], output_dir: Path, suffixes: Iterable[str]) -> list[Path]:
    """Files a finished prompt wrote, restricted to the output folder."""
    wanted = {suffix.lower() for suffix in suffixes}
    root = output_dir.resolve()
    found: list[Path] = []
    outputs = history_item.get("outputs", {})
    for node_output in outputs.values() if isinstance(outputs, dict) else []:
        if not isinstance(node_output, dict):
            continue
        for key in OUTPUT_KEYS:
            for item in node_output.get(key, []) or []:
                if not isinstance(item, dict) or item.get("type", "output") != "output" or not item.get("filename"):
                    continue
                path = (root / str(item.get("subfolder", "")) / str(item["filename"])).resolve()
                if root in path.parents and path.suffix.lower() in wanted and path.is_file():
                    found.append(path)
    return found


class ComfyServer:
    """A ComfyUI process bound to 127.0.0.1 for the lifetime of one task."""

    def __init__(
        self,
        *,
        models_dir: Path,
        scratch_dir: Path,
        port: int = 8188,
        reserve_vram_gb: float = 1.0,
        startup_timeout: int = 600,
        extra_args: Iterable[str] = (),
    ):
        self.models_dir = models_dir
        self.scratch = scratch_dir
        self.port = port
        self.reserve_vram_gb = reserve_vram_gb
        self.startup_timeout = startup_timeout
        self.extra_args = list(extra_args)
        self.base_url = f"http://127.0.0.1:{port}"
        self.output_dir = scratch_dir / "output"
        self.input_dir = scratch_dir / "input"
        self._process: subprocess.Popen[bytes] | None = None

    def __enter__(self) -> "ComfyServer":
        for child in ("input", "output", "temp", "user"):
            (self.scratch / child).mkdir(parents=True, exist_ok=True)
        paths_file = self.scratch / "extra_model_paths.yaml"
        paths_file.write_text(extra_model_paths(self.models_dir), encoding="utf-8")
        command = [
            sys.executable, "main.py",
            "--listen", "127.0.0.1",
            "--port", str(self.port),
            "--disable-auto-launch",
            "--input-directory", str(self.input_dir),
            "--output-directory", str(self.output_dir),
            "--temp-directory", str(self.scratch / "temp"),
            "--user-directory", str(self.scratch / "user"),
            "--extra-model-paths-config", str(paths_file),
            "--reserve-vram", str(self.reserve_vram_gb),
            *self.extra_args,
        ]
        env = dict(os.environ)
        env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
        log = (self.scratch / "comfyui.log").open("wb")
        self._process = subprocess.Popen(command, cwd=COMFY_ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        log.close()
        try:
            self._wait_ready()
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, *exc: object) -> None:
        process, self._process = self._process, None
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=30)

    def log_tail(self, lines: int = 80) -> str:
        path = self.scratch / "comfyui.log"
        if not path.exists():
            return ""
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])

    def _wait_ready(self) -> None:
        deadline = time.monotonic() + self.startup_timeout
        while time.monotonic() < deadline:
            if self._process is not None and self._process.poll() is not None:
                raise RuntimeError(f"ComfyUI exited during startup:\n{self.log_tail()}")
            try:
                self._json("GET", "/system_stats")
                return
            except (OSError, RuntimeError):
                time.sleep(2)
        raise TimeoutError(f"ComfyUI did not start within {self.startup_timeout}s:\n{self.log_tail()}")

    def _json(self, method: str, path: str, payload: Any = None) -> Any:
        data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            self.base_url + path, data=data, method=method, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            try:
                detail = describe_failure(json.loads(error.read().decode("utf-8", errors="replace")))
            except ValueError:
                detail = "(no JSON body)"
            finally:
                error.close()
            raise RuntimeError(f"ComfyUI {method} {path} failed with {error.code}: {detail}") from None
        return json.loads(raw) if raw else {}

    def require_nodes(self, graph: Mapping[str, Any]) -> None:
        available = self._json("GET", "/object_info")
        missing = sorted(required_nodes(graph) - set(available if isinstance(available, dict) else {}))
        if missing:
            raise RuntimeError(f"this ComfyUI build is missing nodes: {', '.join(missing)}")

    def stage_input(self, source: Path, name: str) -> str:
        """Copy a staged source into ComfyUI's input folder; returns the LoadImage name."""
        shutil.copyfile(source, self.input_dir / name)
        return name

    def run(self, graph: Mapping[str, Any], *, timeout: int) -> dict[str, Any]:
        self.require_nodes(graph)
        queued = self._json("POST", "/prompt", {"prompt": graph, "client_id": str(uuid.uuid4())})
        prompt_id = str(queued.get("prompt_id") or "") if isinstance(queued, dict) else ""
        if not prompt_id:
            raise RuntimeError(f"ComfyUI refused the graph: {describe_failure(queued)}")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            history = self._json("GET", "/history/" + urllib.parse.quote(prompt_id))
            item = history.get(prompt_id) if isinstance(history, dict) else None
            if isinstance(item, dict):
                status = item.get("status", {})
                if status.get("completed"):
                    return item
                if status.get("status_str") in {"error", "failed"}:
                    raise RuntimeError(f"ComfyUI generation failed: {describe_failure(status)}")
            if self._process is not None and self._process.poll() is not None:
                raise RuntimeError(f"ComfyUI exited during generation:\n{self.log_tail()}")
            time.sleep(2)
        raise TimeoutError(f"ComfyUI generation exceeded {timeout}s")
