# Vendored from the open-jev package 0.1.0 under the Apache License 2.0
# (see runners/open-jev/LICENSE). Unmodified apart from this notice.
"""JEV decision head on PyTorch and transformers: one prefill pass per question.

The backbone is loaded in bf16 with the System 1 LoRA attached (unmerged, as
shipped and trained), and the vocabulary head is released because System 1
reads the final hidden state of the last template token through a small fp32
slot head. Questions about one state are
right-padded into token-bounded batches; with causal attention and recurrent
linear attention, positions before the padding are unaffected by it, so each
row's last real token is read exactly.
"""

from __future__ import annotations

import json
from collections.abc import Iterator, Sequence
from pathlib import Path
from typing import Any

from .contract import TEMPLATE_VERSION, Decision, render_prompt
from .service import ScoredBatch

_SLOT_WIDTH = {"noul": 2, "score": 6, "choice": 16}


def _read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def head_layout(model_dir: Path) -> tuple[dict[str, tuple[int, int]], dict[str, float]]:
    """Slot ranges and per-kind temperatures, validated against the template."""
    config = _read_json(model_dir / "judge_config.json")
    slots = config["slots"]
    if slots.get("template_version") != TEMPLATE_VERSION:
        raise ValueError(f"decision head expects template {slots.get('template_version')!r}")
    ranges = {kind: (int(lo), int(hi)) for kind, (lo, hi) in slots["ranges"].items()}
    for kind, width in _SLOT_WIDTH.items():
        lo, hi = ranges[kind]
        if hi - lo != width:
            raise ValueError(f"decision head has {hi - lo} {kind} slots; expected {width}")
    temperatures = {kind: float(value) for kind, value in _read_json(model_dir / "calibration.json")["per_kind"].items()}
    if set(temperatures) != set(_SLOT_WIDTH) or min(temperatures.values()) <= 0:
        raise ValueError("calibration.json must give a positive temperature for noul, choice and score")
    return ranges, temperatures


def token_batches(lengths: Sequence[int], max_batch_tokens: int, max_rows: int) -> Iterator[list[int]]:
    """Group row indices, shortest first, so ``rows * longest`` stays within budget."""
    batch: list[int] = []
    for index in sorted(range(len(lengths)), key=lambda i: (lengths[i], i)):
        width = max([lengths[index]] + [lengths[i] for i in batch])
        if batch and ((len(batch) + 1) * width > max_batch_tokens or len(batch) >= max_rows):
            yield batch
            batch = []
        batch.append(index)
    if batch:
        yield batch


class JevTorchScorer:
    """Scorer for JEV-format checkpoints (backbone + System 1 LoRA + slot head)."""

    def __init__(
        self,
        model_dir: Path,
        *,
        model_name: str,
        revision: str,
        release_date: str,
        device: str = "cuda",
        max_state_tokens: int = 1024,
        max_batch_tokens: int = 16_384,
        max_rows: int = 32,
    ) -> None:
        import torch
        from peft import PeftModel
        from safetensors.torch import load_file
        from transformers import AutoModelForCausalLM, AutoTokenizer

        self._torch = torch
        self.model_name, self.revision, self.release_date = model_name, revision, release_date
        self._device = device
        self._max_state_tokens = max_state_tokens
        self._max_batch_tokens = max_batch_tokens
        self._max_rows = max_rows
        self._ranges, self._temperatures = head_layout(model_dir)
        self._tokenizer = AutoTokenizer.from_pretrained(str(model_dir), local_files_only=True)
        pad = self._tokenizer.pad_token_id
        self._pad_id = int(pad if pad is not None else self._tokenizer.eos_token_id)
        base = AutoModelForCausalLM.from_pretrained(
            str(model_dir), dtype=torch.bfloat16, device_map=device, local_files_only=True
        )
        # The adapter stays unmerged: merging it into bf16 weights adds a
        # rounding step the checkpoint was never trained or evaluated with.
        adapted = PeftModel.from_pretrained(base, str(model_dir / "adapter"), is_trainable=False)
        causal = adapted.base_model.model
        del causal.lm_head
        self._backbone = causal.model.eval()
        self._adapted = adapted
        del base
        if device.startswith("cuda"):
            torch.cuda.empty_cache()
        head = load_file(str(model_dir / "head.safetensors"), device=device)
        self._weight = head["proj.weight"].float()
        self._bias = head["proj.bias"].float()

    def _encode(self, text: str) -> list[int]:
        return list(self._tokenizer(text, add_special_tokens=False)["input_ids"])

    def _fit_state(self, state: str) -> tuple[str, int, bool]:
        ids = self._encode(state)
        if len(ids) <= self._max_state_tokens:
            return state, len(ids), False
        head = (self._max_state_tokens * 3) // 5
        tail = self._max_state_tokens - head
        text = self._tokenizer.decode(ids[:head]) + "\n...\n" + self._tokenizer.decode(ids[-tail:])
        return text, self._max_state_tokens, True

    def _last_hidden(self, sequences: list[list[int]]) -> Any:
        torch = self._torch
        width = max(len(sequence) for sequence in sequences)
        ids = torch.full((len(sequences), width), self._pad_id, dtype=torch.long)
        mask = torch.zeros((len(sequences), width), dtype=torch.long)
        for row, sequence in enumerate(sequences):
            ids[row, : len(sequence)] = torch.tensor(sequence, dtype=torch.long)
            mask[row, : len(sequence)] = 1
        ids, mask = ids.to(self._device), mask.to(self._device)
        with torch.inference_mode():
            hidden = self._backbone(input_ids=ids, attention_mask=mask).last_hidden_state
            last = torch.tensor([len(sequence) - 1 for sequence in sequences], device=self._device)
            return hidden[torch.arange(len(sequences), device=self._device), last].float()

    def decide(self, state: str, decisions: Sequence[Decision]) -> ScoredBatch:
        torch = self._torch
        fitted, state_tokens, truncated = self._fit_state(state)
        encoded = [self._encode(render_prompt(fitted, decision)) for decision in decisions]
        probabilities: list[list[float]] = [[] for _ in decisions]
        for batch in token_batches([len(row) for row in encoded], self._max_batch_tokens, self._max_rows):
            hidden = self._last_hidden([encoded[index] for index in batch])
            with torch.inference_mode():
                logits = hidden @ self._weight.T + self._bias
            for row, index in zip(logits, batch):
                decision = decisions[index]
                lo, hi = self._ranges[decision.kind]
                width = len(decision.options)
                if width > hi - lo:
                    raise ValueError(f"{decision.name} has more options than the {decision.kind} head")
                z = row[lo : lo + width] / self._temperatures[decision.kind]
                probabilities[index] = torch.softmax(z, dim=0).tolist()
        return ScoredBatch(
            probabilities=probabilities,
            input_tokens=sum(len(row) for row in encoded),
            state_tokens=state_tokens,
            state_truncated=truncated,
        )

    def device_report(self) -> dict[str, Any]:
        torch = self._torch
        if not self._device.startswith("cuda"):
            return {"device": self._device}
        return {
            "device": torch.cuda.get_device_name(0),
            "peak_vram_mib": round(torch.cuda.max_memory_allocated() / 2**20),
            "torch": torch.__version__,
            "cuda": torch.version.cuda,
        }
