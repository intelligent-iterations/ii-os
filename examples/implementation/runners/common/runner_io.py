"""What every runner adapter shares: the request it reads and the files it writes.

Inside a runner container the host has staged (read-only):

    /work/in/inputs.json    the claimed ii-os inputs, every value a string
    /work/in/sources.json   staged source assets in ordinal order
    /work/in/sources/NN.ext the source files themselves

and the adapter writes (the only writable mount):

    /work/out/<artifact>    each output file, plain names only
    /work/out/result.json   {"schema_version": 1, "artifacts": [...], "metadata": {...}}
    /work/out/failure.json  optional {"errorCode": "..."} for a known refusal

Standard library only, so the same code validates a request on the host
(`entrypoint.py plan`) before any image is pulled or model loaded.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
from typing import Any, Iterable, Mapping, Sequence

ERROR_CODE = re.compile(r"^[A-Za-z0-9_.:-]{1,100}$")


class RequestError(ValueError):
    """The request cannot be carried out as given. `code` is reported to ii-os."""

    def __init__(self, message: str, code: str | None = None):
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class Source:
    path: Path
    content_type: str
    kind: str
    ordinal: int
    role: str | None
    size_bytes: int
    asset_id: str = ""


@dataclass(frozen=True)
class Request:
    inputs: dict[str, str]
    sources: list[Source]

    @classmethod
    def load(cls, input_dir: Path) -> "Request":
        root = input_dir.resolve()
        inputs = json.loads((root / "inputs.json").read_text(encoding="utf-8"))
        if not isinstance(inputs, dict) or any(not isinstance(v, str) for v in inputs.values()):
            raise RequestError("inputs.json must be a map of strings")
        sources_file = root / "sources.json"
        raw = json.loads(sources_file.read_text(encoding="utf-8")) if sources_file.exists() else []
        sources = []
        for ordinal, item in enumerate(raw if isinstance(raw, list) else []):
            relative = item.get("file") if isinstance(item, dict) else None
            path = (root / relative).resolve() if isinstance(relative, str) else None
            if path is None or root not in path.parents or item.get("ordinal") != ordinal:
                raise RequestError(f"source {ordinal} is not a staged source file")
            sources.append(
                Source(
                    path=path,
                    content_type=str(item.get("contentType", "")),
                    kind=str(item.get("kind", "")),
                    ordinal=ordinal,
                    role=item.get("role") if isinstance(item.get("role"), str) else None,
                    size_bytes=int(item.get("sizeBytes") or 0),
                    asset_id=str(item.get("assetId") or ""),
                )
            )
        return cls(dict(inputs), sources)


def only(inputs: Mapping[str, str], allowed: Iterable[str]) -> None:
    unexpected = sorted(set(inputs) - set(allowed))
    if unexpected:
        raise RequestError(f"unexpected input: {', '.join(unexpected)}")


def text(inputs: Mapping[str, str], name: str, *, max_length: int, required: bool = True) -> str | None:
    value = inputs.get(name, "").strip()
    if not value:
        if required:
            raise RequestError(f"{name} is required")
        return None
    if len(value) > max_length:
        raise RequestError(f"{name} is longer than {max_length} characters")
    return value


def choice(inputs: Mapping[str, str], name: str, allowed: Sequence[str], *, default: str | None = None) -> str:
    value = inputs.get(name, "").strip() or default
    if value not in allowed:
        raise RequestError(f"{name} must be one of {', '.join(allowed)}")
    return value


def number(
    inputs: Mapping[str, str], name: str, *, minimum: float, maximum: float, required: bool = True, default: float | None = None
) -> float | None:
    raw = inputs.get(name, "").strip()
    if not raw:
        if required and default is None:
            raise RequestError(f"{name} is required")
        return default
    try:
        value = float(raw)
    except ValueError:
        raise RequestError(f"{name} must be a number") from None
    if not math.isfinite(value):
        raise RequestError(f"{name} must be a finite number")
    if not minimum <= value <= maximum:
        raise RequestError(f"{name} must be between {minimum:g} and {maximum:g}")
    return value


def integer(
    inputs: Mapping[str, str], name: str, *, minimum: int, maximum: int, required: bool = True, default: int | None = None
) -> int | None:
    value = number(inputs, name, minimum=minimum, maximum=maximum, required=required, default=default)
    if value is None:
        return None
    if value != int(value):
        raise RequestError(f"{name} must be a whole number")
    return int(value)


def boolean(inputs: Mapping[str, str], name: str, *, default: bool | None = None) -> bool:
    raw = inputs.get(name, "").strip().lower()
    if not raw and default is not None:
        return default
    if raw not in {"true", "false"}:
        raise RequestError(f"{name} must be true or false")
    return raw == "true"


def sources_of(request: Request, kind: str, *, minimum: int, maximum: int) -> list[Source]:
    matching = [source for source in request.sources if source.kind == kind]
    if len(matching) != len(request.sources):
        raise RequestError(f"this task reads {kind} sources only")
    if not minimum <= len(matching) <= maximum:
        raise RequestError(f"this task needs {minimum} to {maximum} {kind} source(s); it received {len(matching)}")
    return matching


@dataclass(frozen=True)
class Artifact:
    file: str
    content_type: str
    poster_for: str | None = None
    # Only for a documented fixed location under the request prefix, e.g.
    # "open-jev/decisions.json"; otherwise the host names the object.
    object_path: str | None = None

    def to_json(self) -> dict[str, str]:
        value = {"file": self.file, "contentType": self.content_type}
        if self.poster_for is not None:
            value.update(role="poster", posterFor=self.poster_for)
        if self.object_path is not None:
            value["objectPath"] = self.object_path
        return value


def write_result(output_dir: Path, artifacts: Sequence[Artifact], metadata: Mapping[str, Any] | None = None) -> None:
    document: dict[str, Any] = {"schema_version": 1, "artifacts": [item.to_json() for item in artifacts]}
    if metadata:
        document["metadata"] = dict(metadata)
    (output_dir / "result.json").write_text(json.dumps(document, sort_keys=False) + "\n", encoding="utf-8")


def write_failure(output_dir: Path, code: str) -> None:
    if not ERROR_CODE.fullmatch(code):
        raise ValueError("failure codes are stable identifiers")
    (output_dir / "failure.json").write_text(json.dumps({"errorCode": code}) + "\n", encoding="utf-8")


def write_github_output(path: str, values: Mapping[str, str]) -> None:
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in values.items():
            if "\n" in value:
                raise ValueError(f"plan output {key} contains a line break")
            handle.write(f"{key}={value}\n")


def options(prefix: str = "II_OS_OPTION_") -> dict[str, str]:
    """Operator tuning passed through the container launcher (II_OS_OPTION_*)."""
    return {key[len(prefix):].lower(): value for key, value in os.environ.items() if key.startswith(prefix)}
