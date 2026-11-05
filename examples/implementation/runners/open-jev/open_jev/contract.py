# Vendored from the open-jev package 0.1.0 under the Apache License 2.0
# (see runners/open-jev/LICENSE). Unmodified apart from this notice.
"""TypeSafe System One request contract, validated and flattened for a decision head.

The request and response shapes follow TypeSafe's published OpenAPI document for
``POST /v1/systemone`` (also served by OpenRouter at ``/api/alpha/decisions``).
Shapes the open model was not trained on are refused with HTTP 400 instead of
being approximated: image assets and ``box`` questions, ``choice`` questions with
more options than the head has slots, and ``score`` rubrics that are not the
model's 0-5 scale.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

RENDER_VERSION = "render-v1"
TEMPLATE_VERSION = "bare-v1"
NOUL_OPTIONS = ("false", "true")
SCORE_LEVELS = 6
SCORE_OPTIONS = tuple(str(level) for level in range(SCORE_LEVELS))
CHOICE_LABELS = "ABCDEFGHIJKLMNOP"
MAX_CHOICE_OPTIONS = len(CHOICE_LABELS)
QUESTION_TYPES = ("noul", "choice", "score", "box")
_IMAGE_KEYS = frozenset({"image", "image_url", "input_image"})


@dataclass(frozen=True)
class Limits:
    """Hard request bounds, enforced before any model work begins."""

    max_questions: int = 64
    max_state_chars: int = 64_000
    max_text_chars: int = 8_000
    max_name_chars: int = 128


class RequestError(Exception):
    """A well-formed request this model cannot answer (HTTP 400)."""

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class SchemaError(Exception):
    """A request that fails the schema (HTTP 422, TypeSafe ``detail`` list)."""

    def __init__(self, errors: list[dict[str, Any]]) -> None:
        super().__init__(errors[0]["msg"] if errors else "invalid request")
        self.errors = errors


@dataclass(frozen=True)
class Decision:
    """One question flattened into the decision template."""

    name: str
    kind: str
    question: str
    options: tuple[str, ...]
    lines: tuple[str, ...]
    legend: dict[str, Any] | None = None


@dataclass(frozen=True)
class ParsedRequest:
    model: str
    state: str
    decisions: tuple[Decision, ...] = field(default_factory=tuple)


def text_of(value: Any) -> str:
    """Render a TypeSafe ``string | object | array | null`` value as text."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


def render_prompt(state: str, decision: Decision) -> str:
    """The ``bare-v1`` template the JEV decision head was trained on."""
    return (
        f"[kind] {decision.kind}\n[state] {state}\n[question] {decision.question}\n"
        "[options]\n" + "\n".join(decision.lines) + "\n[decision]:"
    )


def _error(loc: list[Any], msg: str, kind: str, value: Any = None) -> dict[str, Any]:
    error: dict[str, Any] = {"loc": ["body", *loc], "msg": msg, "type": kind}
    if value is not None:
        preview = value if isinstance(value, str) else json.dumps(value)[:200]
        error["input"] = preview[:200]
    return error


def _is_image(part: Any) -> bool:
    if not isinstance(part, dict):
        return False
    return bool(_IMAGE_KEYS & set(part)) or part.get("type") in _IMAGE_KEYS


def _state_text(state: Any, limits: Limits) -> str:
    if isinstance(state, list):
        if any(_is_image(part) for part in state):
            raise RequestError("image state parts are not supported by this text-only model")
        text = "\n".join(text_of(part) for part in state)
    elif _is_image(state):
        raise RequestError("image state parts are not supported by this text-only model")
    else:
        text = text_of(state)
    if len(text) > limits.max_state_chars:
        raise RequestError(f"state is {len(text)} characters; the limit is {limits.max_state_chars}")
    return text


def _bounded(value: Any, where: str, limits: Limits) -> str:
    text = text_of(value)
    if len(text) > limits.max_text_chars:
        raise RequestError(f"{where} is {len(text)} characters; the limit is {limits.max_text_chars}")
    return text


def _noul(name: str, raw: dict[str, Any], instructions: str, limits: Limits) -> Decision:
    criteria = raw.get("criteria") or {}
    parts = [
        f"{key}: {_bounded(criteria[key], f'{name}.criteria.{key}', limits)}"
        for key in ("true", "false")
        if criteria.get(key) not in (None, "")
    ]
    question = f"{instructions} ({'; '.join(parts)})" if parts else instructions
    return Decision(name, "noul", question, NOUL_OPTIONS, NOUL_OPTIONS)


def _choice(name: str, raw: dict[str, Any], instructions: str, limits: Limits) -> Decision:
    criteria: dict[str, Any] = raw["criteria"]
    if len(criteria) > MAX_CHOICE_OPTIONS:
        raise RequestError(
            f"question '{name}' has {len(criteria)} choices; this model decides over at most "
            f"{MAX_CHOICE_OPTIONS}"
        )
    lines = []
    for index, (option, description) in enumerate(criteria.items()):
        if len(option) > limits.max_name_chars:
            raise RequestError(f"question '{name}' has a choice name over {limits.max_name_chars} characters")
        detail = _bounded(description, f"{name}.criteria.{option}", limits)
        label = CHOICE_LABELS[index]
        lines.append(f"{label}) {option}: {detail}" if detail else f"{label}) {option}")
    return Decision(name, "choice", instructions, tuple(criteria), tuple(lines))


def _score(name: str, raw: dict[str, Any], instructions: str, limits: Limits) -> Decision:
    levels: list[Any] = raw["criteria"]
    if len(levels) != SCORE_LEVELS:
        raise RequestError(
            f"question '{name}' has {len(levels)} score levels; this model scores on exactly "
            f"{SCORE_LEVELS} ordered levels (0-5)"
        )
    rubric = "; ".join(
        f"{level} = {_bounded(value, f'{name}.criteria[{level}]', limits)}"
        for level, value in enumerate(levels)
    )
    question = f"{instructions}\nRate on a 0-5 scale: {rubric}".lstrip("\n")
    legend = {str(level): value for level, value in enumerate(levels)}
    return Decision(name, "score", question, SCORE_OPTIONS, SCORE_OPTIONS, legend)


def _schema_errors(name: str, raw: Any) -> list[dict[str, Any]]:
    loc = ["questions", name]
    if not isinstance(raw, dict):
        return [_error(loc, "Input should be a valid dictionary", "dict_type", raw)]
    kind = raw.get("type")
    if kind not in QUESTION_TYPES:
        return [_error([*loc, "type"], "Input tag does not match noul, choice, score or box", "union_tag_invalid", kind)]
    criteria = raw.get("criteria")
    if kind == "noul" and criteria is not None:
        if not isinstance(criteria, dict) or set(criteria) - {"true", "false"}:
            return [_error([*loc, "criteria"], "Criteria may only contain 'true' and 'false'", "extra_forbidden", criteria)]
    if kind == "choice":
        if not isinstance(criteria, dict):
            return [_error([*loc, "criteria"], "Input should be a valid dictionary", "dict_type", criteria)]
        if not 1 <= len(criteria) <= 255:
            return [_error([*loc, "criteria"], "Criteria should have 1 to 255 choices", "too_long", criteria)]
    if kind == "score":
        if not isinstance(criteria, list):
            return [_error([*loc, "criteria"], "Input should be a valid list", "list_type", criteria)]
        if not 1 <= len(criteria) <= 10:
            return [_error([*loc, "criteria"], "Criteria should have 1 to 10 levels", "too_long", criteria)]
    return []


def parse_request(body: Any, limits: Limits = Limits()) -> ParsedRequest:
    """Validate a System One request body and flatten every question."""
    if not isinstance(body, dict):
        raise SchemaError([_error([], "Input should be a valid dictionary", "dict_type", body)])
    errors = [_error([key], "Field required", "missing") for key in ("model", "state", "questions") if key not in body]
    if "model" in body and not isinstance(body["model"], str):
        errors.append(_error(["model"], "Input should be a valid string", "string_type", body["model"]))
    if "state" in body and not isinstance(body["state"], (str, dict, list)):
        errors.append(_error(["state"], "Input should be a string, object or array", "union_type", body["state"]))
    questions = body.get("questions")
    if "questions" in body and (not isinstance(questions, dict) or not questions):
        errors.append(_error(["questions"], "Questions should have at least 1 entry", "too_short", questions))
    if errors:
        raise SchemaError(errors)
    assert isinstance(questions, dict)
    errors = [error for name, raw in questions.items() for error in _schema_errors(name, raw)]
    if errors:
        raise SchemaError(errors)
    if body.get("assets"):
        raise RequestError("image assets are not supported by this text-only model")
    if len(questions) > limits.max_questions:
        raise RequestError(f"request has {len(questions)} questions; the limit is {limits.max_questions}")
    state = _state_text(body["state"], limits)
    decisions = []
    for name, raw in questions.items():
        if not name or len(name) > limits.max_name_chars:
            raise RequestError(f"question names must be 1 to {limits.max_name_chars} characters")
        if raw["type"] == "box":
            raise RequestError(f"question '{name}' is a box question; this text-only model has no box head")
        instructions = _bounded(raw.get("instructions"), f"{name}.instructions", limits)
        build = {"noul": _noul, "choice": _choice, "score": _score}[raw["type"]]
        decisions.append(build(name, raw, instructions, limits))
    return ParsedRequest(model=body["model"], state=state, decisions=tuple(decisions))
