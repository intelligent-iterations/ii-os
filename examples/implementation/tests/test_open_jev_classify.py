"""open-jev classify: request validation, refusals that carry the classification
error code, the decisions document the dashboard reads, the pinned model
folder, and the workflow wiring for classification-open-jev-9b."""

from __future__ import annotations

import contextlib
import io
import json
import math
import sys
from types import SimpleNamespace
import unittest

from tests.support import KIT_ROOT, RUNNERS, TempDir, load

RUNNER = RUNNERS / "open-jev"
if str(RUNNER) not in sys.path:
    sys.path.insert(0, str(RUNNER))

runner_io = load("runners/common/runner_io.py", "runner_io")
runner_entry = load("runners/common/runner_entry.py", "runner_entry")
task = load("runners/open-jev/tasks/classify.py", "kit_open_jev_classify")
entrypoint = load("runners/open-jev/entrypoint.py", "kit_open_jev_entrypoint")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")
publish = load("scripts/ii_os_publish.py", "ii_os_publish")

from open_jev.service import ScoredBatch  # noqa: E402

STATE = "acme-co says the example-app invoice charged them twice this month."
SECRET = "acme-private-wording"
QUESTIONS = {
    "billing": {"type": "noul", "instructions": "Is this message about billing?"},
    "tone": {"type": "choice", "instructions": "What is the tone?", "criteria": {"angry": "An upset message", "calm": None}},
    "urgency": {
        "type": "score",
        "instructions": "How urgent is this message?",
        "criteria": ["None", "Very low", "Low", "Moderate", "High", "Very high"],
    },
}
REVISION = "7ac669b8fb476ba926491e3d1c39f9330d68dbed"
WORKFLOW = KIT_ROOT / ".github" / "workflows" / "open-jev-classification.yml"


def inputs(asked: object = None, **overrides: str) -> dict[str, str]:
    """Claimed inputs: `asked` is encoded as the questions JSON; overrides are raw strings."""
    encoded = json.dumps(QUESTIONS if asked is None else asked)
    return {"state": STATE, "questions": encoded, **overrides}


def request(asked: object = None, **overrides: str) -> runner_io.Request:
    return runner_io.Request(inputs=inputs(asked, **overrides), sources=[])


class FakeScorer:
    model_name = "autotrust/JEV-9B"
    revision = REVISION
    release_date = "2026-09-23"

    def decide(self, state, decisions):
        rows = [[1.0] * (len(decision.options) - 1) + [3.0] for decision in decisions]
        return ScoredBatch(rows, input_tokens=40 * len(decisions), state_tokens=18, state_truncated=False)

    def device_report(self) -> dict:
        return {"device": "Example 24 GB GPU", "peak_vram_mib": 16100}


def assert_dashboard_reads(test: unittest.TestCase, document: dict) -> None:
    """The checks ClassificationDecisions.fromDocument makes in the ii-os client."""
    test.assertEqual(document["schema_version"], 1)
    response, run = document["response"], document["run"]
    test.assertEqual(set(response), {"model", "answers", "usage"})
    test.assertTrue(response["answers"])
    test.assertIsInstance(response["usage"]["input_tokens"], int)
    for field in ("model", "model_revision"):
        test.assertIsInstance(run[field], str)
        test.assertTrue(run[field])

    def probability(value: object) -> None:
        test.assertIsInstance(value, (int, float))
        test.assertTrue(math.isfinite(value) and 0 <= value <= 1, value)

    for name, item in response["answers"].items():
        with test.subTest(answer=name):
            test.assertIn(item["type"], {"choice", "noul", "score"})
            if item["type"] == "noul":
                probability(item["noul"])
                continue
            probability(item["confidence"])
            test.assertTrue(item["probabilities"])
            for share in item["probabilities"].values():
                probability(share)
            if item["type"] == "choice":
                test.assertIsInstance(item["choice"], str)
            else:
                test.assertIsInstance(item["score"], (int, float))
                test.assertIsInstance(item["legend"], dict)


class PlanTest(unittest.TestCase):
    def test_plan_names_the_pinned_model_profile_and_nothing_else(self) -> None:
        self.assertEqual(task.plan(request()), {"profile": "jev-9b"})

    def test_state_and_questions_are_required_and_bounded(self) -> None:
        for name, value in (("state", " "), ("state", "x" * 8001), ("questions", ""), ("questions", "{" * 32001)):
            with self.subTest(field=name, length=len(value)), self.assertRaisesRegex(runner_io.RequestError, name):
                task.plan(request(**{name: value}))

    def test_the_longest_catalog_inputs_are_accepted(self) -> None:
        self.assertEqual(task.plan(request(state="x" * 8000))["profile"], "jev-9b")

    def test_inputs_the_catalog_does_not_declare_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt="x"))

    def test_this_task_reads_no_source_assets(self) -> None:
        with_source = runner_io.Request(inputs=inputs(), sources=[object()])  # type: ignore[list-item]
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(with_source)


class RequestTest(unittest.TestCase):
    def assert_rejected(self, questions: object, fragment: str, **overrides: str) -> None:
        with self.assertRaises(runner_io.RequestError) as raised:
            task.system_one_request(inputs(questions, **overrides))
        error = raised.exception
        self.assertEqual(error.code, "classification_request_rejected")
        self.assertIn(fragment, str(error))
        for private in (SECRET, STATE, "acme-co"):
            self.assertNotIn(private, str(error))

    def test_builds_the_system_one_request(self) -> None:
        self.assertEqual(
            task.system_one_request(inputs()),
            {"model": "autotrust/JEV-9B", "state": STATE, "questions": QUESTIONS},
        )

    def test_questions_must_be_a_json_object_of_one_to_eight_questions(self) -> None:
        with self.assertRaises(runner_io.RequestError) as raised:
            task.system_one_request({"state": STATE, "questions": "{not json"})
        self.assertEqual(raised.exception.code, "classification_request_rejected")
        self.assertIn("questions", str(raised.exception))
        for questions in ([], {}, {f"q{i}": {"type": "noul"} for i in range(9)}):
            with self.subTest(questions=questions):
                self.assert_rejected(questions, "questions")

    def test_shapes_the_model_was_not_trained_on_are_rejected_by_kind(self) -> None:
        many = {f"{SECRET}-{i}": None for i in range(17)}
        cases = {
            "box question": {SECRET: {"type": "box", "instructions": SECRET}},
            "more than 16 choices": {SECRET: {"type": "choice", "criteria": many}},
            "six levels": {SECRET: {"type": "score", "criteria": [SECRET, "b", "c"]}},
            "longer than its limit": {SECRET: {"type": "noul", "instructions": SECRET * 401}},
            "name over 128": {SECRET * 10: {"type": "noul"}},
        }
        for fragment, questions in cases.items():
            with self.subTest(fragment=fragment):
                self.assert_rejected(questions, fragment)

    def test_schema_failures_are_rejected_without_echoing_the_questions(self) -> None:
        self.assert_rejected({SECRET: {"type": SECRET}}, "union_tag_invalid")
        self.assert_rejected({SECRET: {"type": "choice"}}, "dict_type")
        self.assert_rejected({SECRET: {"type": "noul", "criteria": {SECRET: "x"}}}, "extra_forbidden")
        self.assert_rejected({SECRET: SECRET}, "dict_type")

    def test_an_over_long_state_is_rejected_at_run_time_too(self) -> None:
        self.assert_rejected(None, "state", state="x" * 8001)


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.work = self.temp.path / "work"
        self.output_dir = self.work / "out"
        self.output_dir.mkdir(parents=True)
        self.loaded: list = []
        self.context = SimpleNamespace(
            models_dir=self.temp.path / "models", output_dir=self.output_dir, scratch_dir=self.temp.path / "scratch", options={}
        )
        self.original_loader = task._load_scorer

        def fake_loader(model_dir):
            self.loaded.append(model_dir)
            return FakeScorer()

        task._load_scorer = fake_loader

    def tearDown(self) -> None:
        task._load_scorer = self.original_loader
        self.temp.cleanup()

    def classify(self, req: runner_io.Request | None = None):
        req = req or request()
        return task.run(task.plan(req), req, self.context)

    def test_run_writes_the_decisions_document_the_dashboard_reads(self) -> None:
        artifacts, _ = self.classify()
        self.assertEqual(
            [item.to_json() for item in artifacts],
            [{"file": "decisions.json", "contentType": "application/json", "objectPath": "open-jev/decisions.json"}],
        )
        self.assertEqual(self.loaded, [self.context.models_dir / "jev-9b"])
        document = json.loads((self.output_dir / "decisions.json").read_text(encoding="utf-8"))
        assert_dashboard_reads(self, document)
        response, run = document["response"], document["run"]
        self.assertEqual(response["model"], "autotrust/JEV-9B")
        self.assertEqual(set(response["answers"]), set(QUESTIONS))
        self.assertEqual(response["answers"]["tone"]["choice"], "calm")
        self.assertEqual(response["answers"]["urgency"]["legend"]["5"], "Very high")
        self.assertEqual(response["usage"], {"input_tokens": 120, "output_tokens": 0})
        self.assertEqual(run["model"], "autotrust/JEV-9B")
        self.assertEqual(run["model_revision"], REVISION)
        self.assertEqual((run["template_version"], run["render_version"]), ("bare-v1", "render-v1"))
        self.assertEqual((run["questions"], run["state_tokens"], run["state_truncated"]), (3, 18, False))
        self.assertEqual(run["device"], "Example 24 GB GPU")
        self.assertIsInstance(run["load_seconds"], float)
        self.assertIsInstance(run["decide_seconds"], float)

    def test_the_document_passes_the_kit_publisher(self) -> None:
        artifacts, metadata = self.classify()
        runner_io.write_result(self.output_dir, artifacts, metadata)
        planned = publish.plan(
            self.work,
            object_prefix="workspaces/acme-co/runs/request-1/",
            run_id=7,
            run_attempt=1,
            allowed_content_types=("application/json",),
            max_bytes=1048576,
        )
        self.assertEqual([item.content_type for item in planned], ["application/json"])
        # The dashboard reads decisions from this documented path under the request prefix.
        self.assertEqual([item.object_name for item in planned], ["workspaces/acme-co/runs/request-1/open-jev/decisions.json"])

    def test_the_result_metadata_carries_no_request_text(self) -> None:
        _, metadata = self.classify()
        text = json.dumps(metadata)
        self.assertEqual(metadata["model_revision"], REVISION)
        for private in (STATE, "billing", "tone", "urgency", "Very high"):
            self.assertNotIn(private, text)

    def test_a_rejected_request_never_loads_the_model(self) -> None:
        req = request({"q": {"type": "box"}})
        with self.assertRaises(runner_io.RequestError) as raised:
            task.run({"profile": "jev-9b"}, req, self.context)
        self.assertEqual(raised.exception.code, "classification_request_rejected")
        self.assertEqual(self.loaded, [])
        self.assertFalse((self.output_dir / "decisions.json").exists())

    def test_the_entrypoint_hands_the_rejection_code_to_the_failure_report(self) -> None:
        input_dir = self.work / "in"
        input_dir.mkdir()
        (input_dir / "inputs.json").write_text(json.dumps(inputs({SECRET: {"type": "box", "instructions": SECRET}})))
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed), contextlib.redirect_stderr(printed):
            status = runner_entry.main(
                ["run", "--task", "classify", "--input-dir", str(input_dir), "--output-dir", str(self.output_dir),
                 "--models-dir", str(self.context.models_dir), "--scratch-dir", str(self.context.scratch_dir)],
                {"classify": task.__name__},
            )
        self.assertEqual(status, 2)
        self.assertEqual(json.loads((self.output_dir / "failure.json").read_text()), {"errorCode": "classification_request_rejected"})
        self.assertEqual(
            publish.failure_code(self.work, default="classification_workflow_failed", allowed=("classification_request_rejected",)),
            "classification_request_rejected",
        )
        self.assertNotIn(SECRET, printed.getvalue())
        self.assertNotIn(STATE, printed.getvalue())


class ModelFolderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = models.load_manifest(RUNNER / "models.json")
        self.profile = self.manifest.profiles["jev-9b"]

    def test_the_profile_is_the_pinned_jev_9b_snapshot(self) -> None:
        self.assertEqual(self.manifest.runner, "open-jev")
        self.assertEqual(list(self.manifest.profiles), ["jev-9b"])
        self.assertEqual(len(self.profile), 14)
        for name in ("config.json", "model.safetensors.index.json", "judge_config.json", "calibration.json", "head.safetensors",
                     "adapter/adapter_config.json", "adapter/adapter_model.safetensors", "tokenizer.json", "tokenizer_config.json"):
            self.assertIn(f"jev-9b/{name}", self.profile)
        self.assertEqual(len([path for path in self.profile if path.startswith("jev-9b/model-0000")]), 5)
        self.assertEqual(sum(self.manifest.files[path].size_bytes for path in self.profile), 18_088_575_127)

    def test_every_file_is_hash_pinned_to_the_upstream_commit(self) -> None:
        self.assertEqual(task.REVISION, REVISION)
        for path in self.profile:
            item = self.manifest.files[path]
            with self.subTest(path=path):
                upstream = path.removeprefix(f"{task.MODEL_FOLDER}/")
                self.assertEqual(item.source, f"https://huggingface.co/autotrust/JEV-9B/resolve/{REVISION}/{upstream}")
                self.assertIsNotNone(item.sha256)
                self.assertEqual(item.license, "Apache-2.0")
                self.assertFalse(item.optional)


class WorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WORKFLOW.read_text(encoding="utf-8")

    def test_the_entrypoint_serves_the_workflow_task(self) -> None:
        self.assertEqual(entrypoint.TASKS, {"classify": "tasks.classify"})
        self.assertIn("      RUNNER_NAME: open-jev\n      RUNNER_TASK: classify\n", self.text)

    def test_the_workflow_declares_the_catalog_inputs_and_outputs(self) -> None:
        for name in ("ii_request_id", "ii_payload_mode", "state", "questions"):
            self.assertIn(f"\n      {name}:\n", self.text)
        self.assertIn("allowed-content-types: application/json\n", self.text)
        self.assertIn('max-bytes: "1048576"\n', self.text)
        self.assertIn("--gpu", self.text)
        self.assertIn("vars.II_OS_RUNNER_IMAGE_OPEN_JEV", self.text)
        self.assertIn("    timeout-minutes: 45\n", self.text)

    def test_failures_carry_the_codes_the_dashboard_maps(self) -> None:
        self.assertEqual(task.REJECTED, "classification_request_rejected")
        self.assertIn(f"runner-error-codes: {task.REJECTED},classification_model_missing\n", self.text)
        self.assertEqual(self.text.count("error-code: classification_workflow_failed\n"), 2)
        self.assertEqual(self.text.count("cancelled-error-code: classification_workflow_cancelled\n"), 2)

    def test_a_missing_model_is_reported_as_its_own_code(self) -> None:
        step = self.text.split("      - name: Check the model folder\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("WORK_DIR: ${{ steps.claim.outputs.work-dir }}", step)
        self.assertIn('--work-dir "${WORK_DIR}" --failure-code classification_model_missing', step)


if __name__ == "__main__":
    unittest.main()
