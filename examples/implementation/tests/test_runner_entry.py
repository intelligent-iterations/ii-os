"""The generic runner entrypoint: plan on the host, run in the container."""

from __future__ import annotations

import json
import sys
import types
import unittest

from tests.support import TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
runner_entry = load("runners/common/runner_entry.py", "runner_entry")


def fake_task() -> types.ModuleType:
    module = types.ModuleType("kit_fake_task")

    def plan(request):
        runner_io.only(request.inputs, {"prompt", "fail"})
        prompt = runner_io.text(request.inputs, "prompt", max_length=20)
        if request.inputs.get("fail") == "refuse":
            raise runner_io.RequestError("the model refused", code="example_request_rejected")
        return {"profile": "example-profile", "prompt": prompt}

    def run(plan, request, context):
        (context.output_dir / "image.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        return [runner_io.Artifact("image.png", "image/png")], {"prompt_length": len(plan["prompt"])}

    module.plan, module.run = plan, run
    sys.modules[module.__name__] = module
    return module


class EntryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.input_dir = self.temp.path / "in"
        self.output_dir = self.temp.path / "out"
        self.input_dir.mkdir()
        self.output_dir.mkdir()
        self.tasks = {"example": fake_task().__name__}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def invoke(self, command: str, inputs: dict[str, str], *extra: str) -> int:
        (self.input_dir / "inputs.json").write_text(json.dumps(inputs))
        return runner_entry.main(
            [
                command, "--task", "example",
                "--input-dir", str(self.input_dir),
                "--output-dir", str(self.output_dir),
                "--models-dir", str(self.temp.path),
                "--scratch-dir", str(self.temp.path / "scratch"),
                *extra,
            ],
            self.tasks,
        )

    def test_plan_writes_the_model_profile_for_the_folder_check(self) -> None:
        output = self.temp.path / "github_output"
        self.assertEqual(self.invoke("plan", {"prompt": "hello"}, "--github-output", str(output)), 0)
        self.assertEqual(output.read_text(), "profile=example-profile\n")
        self.assertFalse((self.output_dir / "result.json").exists())

    def test_run_writes_the_result_manifest(self) -> None:
        self.assertEqual(self.invoke("run", {"prompt": "hello"}), 0)
        result = json.loads((self.output_dir / "result.json").read_text())
        self.assertEqual(result["artifacts"], [{"file": "image.png", "contentType": "image/png"}])
        self.assertEqual(result["metadata"], {"prompt_length": 5})

    def test_a_refused_request_fails_with_its_code_and_writes_no_result(self) -> None:
        self.assertEqual(self.invoke("run", {"prompt": "hello", "fail": "refuse"}), 2)
        self.assertEqual(json.loads((self.output_dir / "failure.json").read_text()), {"errorCode": "example_request_rejected"})
        self.assertFalse((self.output_dir / "result.json").exists())

    def test_an_invalid_request_fails_at_plan_time(self) -> None:
        self.assertEqual(self.invoke("plan", {"prompt": ""}), 2)
        self.assertEqual(self.invoke("plan", {"prompt": "x", "unexpected": "y"}), 2)

    def test_an_unknown_task_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            runner_entry.main(["plan", "--task", "../../evil", "--input-dir", str(self.input_dir)], self.tasks)


if __name__ == "__main__":
    unittest.main()
