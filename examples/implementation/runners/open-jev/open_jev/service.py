# Vendored from the open-jev package 0.1.0 under the Apache License 2.0
# (see runners/open-jev/LICENSE). Changed: removed the model listing that only
# the HTTP server used.
"""Provider-neutral System One service: contract in, scorer, contract out."""

from __future__ import annotations

import time
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any, Protocol

from .answers import answer
from .contract import RENDER_VERSION, TEMPLATE_VERSION, Decision, Limits, RequestError, parse_request


@dataclass(frozen=True)
class ScoredBatch:
    """Distributions for every decision about one state, plus token accounting."""

    probabilities: list[list[float]]
    input_tokens: int
    state_tokens: int
    state_truncated: bool


class Scorer(Protocol):
    """A decision model. Implementations own tokenisation and device placement."""

    model_name: str
    revision: str
    release_date: str

    def decide(self, state: str, decisions: Sequence[Decision]) -> ScoredBatch: ...


@dataclass(frozen=True)
class ServiceConfig:
    aliases: tuple[str, ...]
    limits: Limits = Limits()


@dataclass(frozen=True)
class SystemOneResult:
    """The TypeSafe response body and out-of-band run metadata."""

    body: dict[str, Any]
    meta: dict[str, Any]


def accepted_models(scorer: Scorer, config: ServiceConfig) -> tuple[str, ...]:
    names = [scorer.model_name, *config.aliases]
    return tuple(dict.fromkeys(name for name in names if name))


def system_one(body: Any, scorer: Scorer, config: ServiceConfig) -> SystemOneResult:
    """Answer one System One request. Raises ``SchemaError`` or ``RequestError``."""
    parsed = parse_request(body, config.limits)
    if parsed.model not in accepted_models(scorer, config):
        raise RequestError(
            f"model '{parsed.model}' is not served here; use one of: "
            + ", ".join(accepted_models(scorer, config))
        )
    started = time.monotonic()
    batch = scorer.decide(parsed.state, parsed.decisions)
    elapsed = time.monotonic() - started
    if len(batch.probabilities) != len(parsed.decisions):
        raise RuntimeError("scorer returned the wrong number of distributions")
    answers = {
        decision.name: answer(decision, probabilities)
        for decision, probabilities in zip(parsed.decisions, batch.probabilities)
    }
    response = {
        "model": scorer.model_name,
        "answers": answers,
        "usage": {"input_tokens": batch.input_tokens, "output_tokens": 0},
    }
    meta = {
        "model": scorer.model_name,
        "model_revision": scorer.revision,
        "template_version": TEMPLATE_VERSION,
        "render_version": RENDER_VERSION,
        "questions": len(parsed.decisions),
        "state_tokens": batch.state_tokens,
        "state_truncated": batch.state_truncated,
        "decide_seconds": round(elapsed, 4),
    }
    return SystemOneResult(body=response, meta=meta)
