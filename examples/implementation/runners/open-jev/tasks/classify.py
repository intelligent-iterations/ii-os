"""Classify one text with open JEV (autotrust/JEV-9B): typed System One questions
answered with calibrated probability distributions in one prefill pass.

Serves the catalog id classification-open-jev-9b. Inputs, from the claim:

    state      the text to classify, 1 to 8,000 characters
    questions  a JSON-encoded TypeSafe System One `questions` object with 1 to 8
               entries (noul, choice with up to 16 options, score on 6 levels)

Writes out/decisions.json, the document the dashboard reads:

    {"schema_version": 1,
     "response": {"model", "answers", "usage"},     # the TypeSafe response body
     "run": {"model", "model_revision", "template_version", "render_version",
             "questions", "state_tokens", "state_truncated", "decide_seconds",
             "load_seconds", "device", ...}}

A request the model cannot answer (a box question, more than 16 choices, a
score that is not six levels, malformed questions, ...) is refused before the
model loads with RequestError code `classification_request_rejected`, which
the entrypoint writes to out/failure.json for the failure report. Refusals name
the field and the kind of problem, never the person's text or question names.
"""

from __future__ import annotations

import json
from pathlib import Path
import time
from typing import Any, Callable, Mapping

import runner_io

INPUTS = {"state", "questions"}
MODEL = "autotrust/JEV-9B"
REVISION = "7ac669b8fb476ba926491e3d1c39f9330d68dbed"
RELEASE_DATE = "2026-09-23"
PROFILE = "jev-9b"
MODEL_FOLDER = "jev-9b"
MAX_STATE_CHARS = 8000
MAX_QUESTIONS_CHARS = 32000
MAX_QUESTIONS = 8
MAX_DOCUMENT_BYTES = 1024 * 1024
OUTPUT = "decisions.json"
REJECTED = "classification_request_rejected"

# What a refusal from the vendored contract was about, matched on its detail
# text (which embeds question names, so it is never logged). First match wins.
_UNANSWERABLE = (
    ("box question", "a box question"),
    ("choice name over", "a choice name over 128 characters"),
    ("question names must be", "a question name over 128 characters"),
    ("choices; this model decides", "more than 16 choices"),
    ("score levels", "a score that is not six levels (0-5)"),
    ("image", "image input"),
    ("questions; the limit", f"more than {MAX_QUESTIONS} questions"),
    ("characters; the limit", "a text longer than its limit"),
)


def plan(request: runner_io.Request) -> dict[str, Any]:
    """Host-side check of the catalog contract. The questions are parsed in the
    container, so a refusal there carries its error code to the failure report."""
    runner_io.only(request.inputs, INPUTS)
    if request.sources:
        raise runner_io.RequestError("classification reads no source assets")
    _state(request.inputs)
    _questions_text(request.inputs)
    return {"profile": PROFILE}


def system_one_request(inputs: Mapping[str, str]) -> dict[str, Any]:
    """The System One request body, refused with REJECTED unless the model can answer it."""
    state = _state(inputs)
    try:
        questions = json.loads(_questions_text(inputs))
    except ValueError:
        raise _refuse("questions is not valid JSON") from None
    if not isinstance(questions, dict) or not 1 <= len(questions) <= MAX_QUESTIONS:
        raise _refuse(f"questions must be a JSON object with 1 to {MAX_QUESTIONS} questions")
    body = {"model": MODEL, "state": state, "questions": questions}
    from open_jev.contract import parse_request

    _answerable(parse_request, body, _limits())
    return body


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    body = system_one_request(request.inputs)
    from open_jev import __version__
    from open_jev.service import ServiceConfig, system_one

    started = time.monotonic()
    scorer = _load_scorer(Path(context.models_dir) / MODEL_FOLDER)
    load_seconds = round(time.monotonic() - started, 3)
    result = _answerable(system_one, body, scorer, ServiceConfig(aliases=(), limits=_limits()))
    document = {
        "schema_version": 1,
        "response": result.body,
        "run": {**result.meta, "load_seconds": load_seconds, **scorer.device_report(), "package_version": __version__},
    }
    data = (json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(data) > MAX_DOCUMENT_BYTES:
        raise RuntimeError(f"the decisions document is {len(data)} bytes; the catalog allows {MAX_DOCUMENT_BYTES}")
    (Path(context.output_dir) / OUTPUT).write_bytes(data)
    facts = ("model", "model_revision", "questions", "state_tokens", "state_truncated", "decide_seconds", "load_seconds")
    # The dashboard reads decisions from `open-jev/decisions.json` under the
    # request prefix (docs/classification-playground.md).
    artifact = runner_io.Artifact(OUTPUT, "application/json", object_path="open-jev/decisions.json")
    return [artifact], {key: document["run"][key] for key in facts}


def _load_scorer(model_dir: Path) -> Any:
    """Load JEV-9B in bf16 on the GPU, offline, from the read-only model folder."""
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("open JEV needs an NVIDIA GPU and none is visible in the container")
    from open_jev.engine import JevTorchScorer

    return JevTorchScorer(model_dir, model_name=MODEL, revision=REVISION, release_date=RELEASE_DATE, device="cuda")


def _limits() -> Any:
    from open_jev.contract import Limits

    return Limits(max_questions=MAX_QUESTIONS, max_state_chars=MAX_STATE_CHARS)


def _answerable(call: Callable[..., Any], *args: Any) -> Any:
    """Run a vendored contract call, mapping its refusals onto REJECTED without their text."""
    from open_jev.contract import RequestError as Unanswerable, SchemaError

    try:
        return call(*args)
    except SchemaError as error:
        kinds = sorted({str(item.get("type", "invalid")) for item in error.errors})
        raise _refuse(f"questions do not match the System One schema ({', '.join(kinds)})") from None
    except Unanswerable as error:
        what = next((phrase for marker, phrase in _UNANSWERABLE if marker in error.detail), "a question shape")
        raise _refuse(f"questions include {what}, which this model cannot answer") from None


def _state(inputs: Mapping[str, str]) -> str:
    # The text is classified exactly as the person wrote it; only blankness is judged after stripping.
    value = inputs.get("state", "")
    if not value.strip():
        raise _refuse("state is required")
    if len(value) > MAX_STATE_CHARS:
        raise _refuse(f"state is longer than {MAX_STATE_CHARS} characters")
    return value


def _questions_text(inputs: Mapping[str, str]) -> str:
    value = inputs.get("questions", "")
    if not value.strip():
        raise _refuse("questions is required")
    if len(value) > MAX_QUESTIONS_CHARS:
        raise _refuse(f"questions is longer than {MAX_QUESTIONS_CHARS} characters")
    return value


def _refuse(message: str) -> runner_io.RequestError:
    return runner_io.RequestError(message, code=REJECTED)
