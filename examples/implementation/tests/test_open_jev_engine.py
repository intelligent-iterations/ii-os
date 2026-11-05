"""open-jev engine (vendored under Apache-2.0): the System One request contract,
answer shapes, the service and token batching.

Standard library only. The GPU engine imports torch, transformers and peft
lazily, so everything here runs without them.
"""

from __future__ import annotations

import json
import sys
import unittest

from tests.support import RUNNERS, TempDir

RUNNER = RUNNERS / "open-jev"
if str(RUNNER) not in sys.path:
    sys.path.insert(0, str(RUNNER))

from open_jev.answers import answer, confidence  # noqa: E402
from open_jev.contract import (  # noqa: E402
    MAX_CHOICE_OPTIONS,
    Limits,
    RequestError,
    SchemaError,
    parse_request,
    render_prompt,
)
from open_jev.engine import head_layout, token_batches  # noqa: E402
from open_jev.service import ScoredBatch, ServiceConfig, system_one  # noqa: E402

MODEL = "autotrust/JEV-9B"


def request(**questions: object) -> dict:
    return {"model": MODEL, "state": "I was charged twice.", "questions": questions}


class FakeScorer:
    model_name = MODEL
    revision = "7ac669b8fb476ba926491e3d1c39f9330d68dbed"
    release_date = "2026-09-23"

    def __init__(self) -> None:
        self.calls: list[tuple[str, list[str]]] = []

    def decide(self, state, decisions):
        self.calls.append((state, [decision.name for decision in decisions]))
        distributions = []
        for decision in decisions:
            weights = [1.0] * len(decision.options)
            weights[-1] = 3.0
            distributions.append(weights)
        return ScoredBatch(distributions, input_tokens=12 * len(decisions), state_tokens=5, state_truncated=False)


CONFIG = ServiceConfig(aliases=("jev-latest",))


class EngineImportTest(unittest.TestCase):
    def test_the_engine_module_loads_without_torch(self) -> None:
        self.assertNotIn("torch", sys.modules)
        self.assertNotIn("transformers", sys.modules)


class SchemaTest(unittest.TestCase):
    def assert_schema_error(self, body: object, loc: list) -> None:
        with self.assertRaises(SchemaError) as raised:
            parse_request(body)
        self.assertIn(loc, [error["loc"] for error in raised.exception.errors])

    def test_missing_top_level_fields_are_schema_errors(self) -> None:
        self.assert_schema_error({"state": "x"}, ["body", "model"])
        self.assert_schema_error({"model": "m", "state": "x"}, ["body", "questions"])

    def test_empty_questions_are_a_schema_error(self) -> None:
        self.assert_schema_error({"model": "m", "state": "x", "questions": {}}, ["body", "questions"])

    def test_an_unknown_question_type_is_a_schema_error(self) -> None:
        self.assert_schema_error(request(q={"type": "rank"}), ["body", "questions", "q", "type"])

    def test_a_choice_needs_criteria(self) -> None:
        self.assert_schema_error(request(q={"type": "choice"}), ["body", "questions", "q", "criteria"])

    def test_score_criteria_must_be_a_list(self) -> None:
        self.assert_schema_error(request(q={"type": "score", "criteria": {"a": 1}}), ["body", "questions", "q", "criteria"])

    def test_noul_criteria_reject_unknown_keys(self) -> None:
        self.assert_schema_error(request(q={"type": "noul", "criteria": {"maybe": "x"}}), ["body", "questions", "q", "criteria"])

    def test_error_detail_has_the_typesafe_shape(self) -> None:
        with self.assertRaises(SchemaError) as raised:
            parse_request({"model": "m"})
        for error in raised.exception.errors:
            self.assertEqual(set(error) - {"input"}, {"loc", "msg", "type"})


class CapabilityTest(unittest.TestCase):
    def assert_refused(self, body: dict, fragment: str, limits: Limits = Limits()) -> None:
        with self.assertRaises(RequestError) as raised:
            parse_request(body, limits)
        self.assertIn(fragment, raised.exception.detail)

    def test_box_questions_are_refused(self) -> None:
        self.assert_refused(request(q={"type": "box", "instructions": "find it"}), "box")

    def test_image_state_is_refused(self) -> None:
        body = request(q={"type": "noul"})
        body["state"] = ["look", {"type": "image_url", "image_url": "https://example.com/a.png"}]
        self.assert_refused(body, "image")

    def test_assets_are_refused(self) -> None:
        body = request(q={"type": "noul"})
        body["assets"] = {"photo": {"type": "image"}}
        self.assert_refused(body, "image assets")

    def test_a_choice_wider_than_the_head_is_refused(self) -> None:
        criteria = {f"o{i}": None for i in range(MAX_CHOICE_OPTIONS + 1)}
        self.assert_refused(request(q={"type": "choice", "criteria": criteria}), "at most 16")

    def test_a_score_must_be_the_six_level_scale(self) -> None:
        self.assert_refused(request(q={"type": "score", "criteria": ["low", "medium", "high"]}), "exactly 6")

    def test_limits_are_enforced_before_model_work(self) -> None:
        limits = Limits(max_questions=1, max_state_chars=5)
        self.assert_refused(request(a={"type": "noul"}, b={"type": "noul"}), "questions", limits)
        self.assert_refused(request(a={"type": "noul"}), "state", limits)


class RenderTest(unittest.TestCase):
    def test_a_choice_renders_letters_and_descriptions(self) -> None:
        parsed = parse_request(request(tone={
            "type": "choice",
            "instructions": "What is the tone?",
            "criteria": {"angry": "An upset message", "calm": None},
        }))
        decision = parsed.decisions[0]
        self.assertEqual(decision.options, ("angry", "calm"))
        self.assertEqual(
            render_prompt(parsed.state, decision),
            "[kind] choice\n[state] I was charged twice.\n[question] What is the tone?\n"
            "[options]\nA) angry: An upset message\nB) calm\n[decision]:",
        )

    def test_a_noul_appends_its_criteria_and_uses_canonical_options(self) -> None:
        parsed = parse_request(request(billing={
            "type": "noul",
            "instructions": "Is this about billing?",
            "criteria": {"true": "money", "false": None},
        }))
        decision = parsed.decisions[0]
        self.assertEqual(decision.question, "Is this about billing? (true: money)")
        self.assertTrue(render_prompt(parsed.state, decision).endswith("[options]\nfalse\ntrue\n[decision]:"))

    def test_a_score_renders_its_rubric_and_keeps_the_legend(self) -> None:
        levels = ["none", "very low", "low", "moderate", "high", "critical"]
        parsed = parse_request(request(urgency={"type": "score", "instructions": "How urgent?", "criteria": levels}))
        decision = parsed.decisions[0]
        self.assertIn("Rate on a 0-5 scale: 0 = none; 1 = very low", decision.question)
        self.assertEqual(decision.legend, {str(i): level for i, level in enumerate(levels)})
        self.assertEqual(decision.lines, ("0", "1", "2", "3", "4", "5"))

    def test_structured_state_and_instructions_render_as_json(self) -> None:
        body = request(q={"type": "noul", "instructions": {"task": "spam?"}})
        body["state"] = {"subject": "Hi", "body": "Buy now"}
        parsed = parse_request(body)
        self.assertEqual(parsed.state, '{"subject": "Hi", "body": "Buy now"}')
        self.assertEqual(parsed.decisions[0].question, '{"task": "spam?"}')

    def test_text_state_parts_are_joined_by_lines(self) -> None:
        body = request(q={"type": "noul"})
        body["state"] = ["first", "second"]
        self.assertEqual(parse_request(body).state, "first\nsecond")


class AnswerTest(unittest.TestCase):
    def test_confidence_bounds(self) -> None:
        self.assertEqual(confidence([1.0, 0.0, 0.0]), 1.0)
        self.assertAlmostEqual(confidence([1 / 3] * 3), 0.0)
        self.assertAlmostEqual(confidence([0.8, 0.1, 0.1]), (3 * 0.8 - 1) / 2)
        self.assertEqual(confidence([1.0]), 1.0)

    def test_a_choice_answer_has_the_typesafe_shape(self) -> None:
        decision = parse_request(request(q={"type": "choice", "criteria": {"a": None, "b": None}})).decisions[0]
        self.assertEqual(
            answer(decision, [0.25, 0.75]),
            {"type": "choice", "choice": "b", "confidence": 0.5, "probabilities": {"a": 0.25, "b": 0.75}},
        )

    def test_a_score_answer_is_the_expected_level(self) -> None:
        decision = parse_request(request(q={"type": "score", "criteria": ["0", "1", "2", "3", "4", "5"]})).decisions[0]
        result = answer(decision, [0, 0, 0.5, 0.5, 0, 0])
        self.assertEqual(result["score"], 2.5)
        self.assertEqual(result["legend"]["5"], "5")
        self.assertEqual(set(result), {"type", "score", "confidence", "legend", "probabilities"})

    def test_a_noul_answer_is_the_probability_of_true(self) -> None:
        decision = parse_request(request(q={"type": "noul"})).decisions[0]
        self.assertEqual(answer(decision, [0.1, 0.9]), {"type": "noul", "noul": 0.9})

    def test_bad_distributions_fail_loudly(self) -> None:
        decision = parse_request(request(q={"type": "noul"})).decisions[0]
        for bad in ([0.5], [0.0, 0.0], [-1.0, 2.0], [float("nan"), 1.0]):
            with self.subTest(distribution=bad), self.assertRaises(ValueError):
                answer(decision, bad)


class ServiceTest(unittest.TestCase):
    def test_one_scorer_call_answers_every_question(self) -> None:
        scorer = FakeScorer()
        result = system_one(
            request(refund={"type": "noul"}, tone={"type": "choice", "criteria": {"calm": None, "angry": None}}), scorer, CONFIG
        )
        self.assertEqual(len(scorer.calls), 1)
        self.assertEqual(set(result.body), {"model", "answers", "usage"})
        self.assertEqual(result.body["answers"]["tone"]["choice"], "angry")
        self.assertEqual(result.body["usage"], {"input_tokens": 24, "output_tokens": 0})
        self.assertEqual(result.meta["model_revision"], FakeScorer.revision)

    def test_aliases_are_accepted_but_the_real_model_is_reported(self) -> None:
        body = request(q={"type": "noul"})
        body["model"] = "jev-latest"
        self.assertEqual(system_one(body, FakeScorer(), CONFIG).body["model"], MODEL)

    def test_an_unknown_model_is_refused_before_scoring(self) -> None:
        scorer = FakeScorer()
        body = request(q={"type": "noul"})
        body["model"] = "example/other-model"
        with self.assertRaises(RequestError):
            system_one(body, scorer, CONFIG)
        self.assertEqual(scorer.calls, [])


class BatchingTest(unittest.TestCase):
    def test_batches_respect_token_and_row_budgets(self) -> None:
        lengths = [10, 300, 20, 290, 15]
        batches = list(token_batches(lengths, max_batch_tokens=600, max_rows=2))
        self.assertEqual(sorted(index for batch in batches for index in batch), list(range(5)))
        for batch in batches:
            self.assertLessEqual(len(batch), 2)
            self.assertLessEqual(len(batch) * max(lengths[i] for i in batch), 600)

    def test_an_oversized_row_still_runs_alone(self) -> None:
        self.assertEqual(list(token_batches([5000], max_batch_tokens=100, max_rows=4)), [[0]])


class HeadLayoutTest(unittest.TestCase):
    RANGES = {"noul": [0, 2], "score": [2, 8], "choice": [8, 24]}
    TEMPERATURES = {"noul": 1.0, "choice": 0.98, "score": 1.01}

    def setUp(self) -> None:
        self.temp = TempDir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write(self, *, template: str = "bare-v1", ranges: dict | None = None, temperatures: dict | None = None) -> None:
        slots = {"ranges": ranges or self.RANGES, "template_version": template}
        (self.temp.path / "judge_config.json").write_text(json.dumps({"slots": slots}))
        (self.temp.path / "calibration.json").write_text(json.dumps({"per_kind": temperatures or self.TEMPERATURES}))

    def test_reads_slot_ranges_and_temperatures(self) -> None:
        self.write()
        ranges, temperatures = head_layout(self.temp.path)
        self.assertEqual(ranges, {"noul": (0, 2), "score": (2, 8), "choice": (8, 24)})
        self.assertEqual(temperatures["choice"], 0.98)

    def test_a_head_for_another_template_is_refused(self) -> None:
        self.write(template="bare-v2")
        with self.assertRaisesRegex(ValueError, "template"):
            head_layout(self.temp.path)

    def test_a_head_with_the_wrong_slot_width_is_refused(self) -> None:
        self.write(ranges={**self.RANGES, "choice": [8, 20]})
        with self.assertRaisesRegex(ValueError, "choice"):
            head_layout(self.temp.path)

    def test_every_kind_needs_a_positive_temperature(self) -> None:
        self.write(temperatures={"noul": 1.0, "choice": 1.0})
        with self.assertRaisesRegex(ValueError, "temperature"):
            head_layout(self.temp.path)
        self.write(temperatures={**self.TEMPERATURES, "score": 0})
        with self.assertRaisesRegex(ValueError, "temperature"):
            head_layout(self.temp.path)


if __name__ == "__main__":
    unittest.main()
