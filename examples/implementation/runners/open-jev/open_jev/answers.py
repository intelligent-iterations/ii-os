# Vendored from the open-jev package 0.1.0 under the Apache License 2.0
# (see runners/open-jev/LICENSE). Unmodified apart from this notice.
"""Turn decision-head distributions into TypeSafe System One answers."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from .contract import Decision

DECIMALS = 4


def confidence(probabilities: Sequence[float]) -> float:
    """Normalised top probability: 1 when all mass is on one option, 0 when uniform.

    TypeSafe does not publish its formula. This one matches the documented
    behaviour (1.0 for a one-hot answer, falling as the spread evens out) and
    is ``(k * p_max - 1) / (k - 1)`` for ``k`` options.
    """
    k = len(probabilities)
    if k <= 1:
        return 1.0
    value = (k * max(probabilities) - 1.0) / (k - 1.0)
    return min(1.0, max(0.0, value))


def _normalised(probabilities: Sequence[float], expected: int) -> list[float]:
    if len(probabilities) != expected:
        raise ValueError(f"scorer returned {len(probabilities)} probabilities for {expected} options")
    if any(p < 0 or p != p for p in probabilities):
        raise ValueError("scorer returned a negative or NaN probability")
    total = float(sum(probabilities))
    if total <= 0:
        raise ValueError("scorer returned an all-zero distribution")
    return [float(p) / total for p in probabilities]


def _round(value: float) -> float:
    return round(value, DECIMALS)


def answer(decision: Decision, probabilities: Sequence[float]) -> dict[str, Any]:
    """One TypeSafe answer object for ``decision``."""
    p = _normalised(probabilities, len(decision.options))
    if decision.kind == "noul":
        return {"type": "noul", "noul": _round(p[1])}
    if decision.kind == "choice":
        best = max(range(len(p)), key=lambda index: (p[index], -index))
        return {
            "type": "choice",
            "choice": decision.options[best],
            "confidence": _round(confidence(p)),
            "probabilities": {option: _round(value) for option, value in zip(decision.options, p)},
        }
    if decision.kind == "score":
        return {
            "type": "score",
            "score": _round(sum(level * value for level, value in enumerate(p))),
            "confidence": _round(confidence(p)),
            "legend": dict(decision.legend or {}),
            "probabilities": {str(level): _round(value) for level, value in enumerate(p)},
        }
    raise ValueError(f"unsupported decision kind {decision.kind!r}")
