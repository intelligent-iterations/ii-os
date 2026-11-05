"""The shared runner adapter library: reading claimed inputs, typed parsing,
and the result/failure files the host validates."""

from __future__ import annotations

import json
import unittest

from tests.support import TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")


class RequestTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.input_dir = self.temp.path / "in"
        (self.input_dir / "sources").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write(self, inputs: dict[str, str], sources: list[dict[str, object]] | None = None) -> None:
        (self.input_dir / "inputs.json").write_text(json.dumps(inputs))
        (self.input_dir / "sources.json").write_text(json.dumps(sources or []))

    def test_reads_inputs_and_resolves_sources_inside_the_input_folder(self) -> None:
        (self.input_dir / "sources" / "00.png").write_bytes(b"png")
        self.write(
            {"prompt": "a lighthouse"},
            [{"file": "sources/00.png", "contentType": "image/png", "kind": "image", "ordinal": 0, "role": None, "sizeBytes": 3, "sha256": "x", "assetId": "a"}],
        )
        request = runner_io.Request.load(self.input_dir)
        self.assertEqual(request.inputs, {"prompt": "a lighthouse"})
        self.assertEqual(request.sources[0].path, self.input_dir / "sources" / "00.png")
        self.assertEqual(request.sources[0].kind, "image")
        self.assertEqual(request.sources[0].asset_id, "a")

    def test_a_source_path_outside_the_input_folder_is_refused(self) -> None:
        self.write({"prompt": "x"}, [{"file": "../secret", "contentType": "image/png", "kind": "image", "ordinal": 0}])
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            runner_io.Request.load(self.input_dir)

    def test_missing_sources_json_means_no_sources(self) -> None:
        (self.input_dir / "inputs.json").write_text(json.dumps({"prompt": "x"}))
        self.assertEqual(runner_io.Request.load(self.input_dir).sources, [])


class ParsingTest(unittest.TestCase):
    def test_required_text_is_trimmed_and_bounded(self) -> None:
        self.assertEqual(runner_io.text({"prompt": " hi "}, "prompt", max_length=10), "hi")
        with self.assertRaisesRegex(runner_io.RequestError, "prompt is required"):
            runner_io.text({"prompt": "   "}, "prompt", max_length=10)
        with self.assertRaisesRegex(runner_io.RequestError, "prompt is longer"):
            runner_io.text({"prompt": "x" * 11}, "prompt", max_length=10)
        self.assertIsNone(runner_io.text({}, "lyrics", max_length=10, required=False))

    def test_numbers_are_parsed_from_strings_with_bounds(self) -> None:
        self.assertEqual(runner_io.integer({"seed": "42"}, "seed", minimum=0, maximum=100), 42)
        self.assertEqual(runner_io.integer({"seed": "42.0"}, "seed", minimum=0, maximum=100), 42)
        self.assertIsNone(runner_io.integer({"seed": ""}, "seed", minimum=0, maximum=100, required=False))
        with self.assertRaisesRegex(runner_io.RequestError, "seed must be a whole number"):
            runner_io.integer({"seed": "4.5"}, "seed", minimum=0, maximum=100)
        with self.assertRaisesRegex(runner_io.RequestError, "between"):
            runner_io.integer({"seed": "101"}, "seed", minimum=0, maximum=100)
        self.assertEqual(runner_io.number({"strength": "0.5"}, "strength", minimum=0, maximum=1), 0.5)
        for bad in ("nan", "inf", "x"):
            with self.subTest(bad=bad), self.assertRaises(runner_io.RequestError):
                runner_io.number({"strength": bad}, "strength", minimum=0, maximum=1)

    def test_booleans_and_choices(self) -> None:
        self.assertTrue(runner_io.boolean({"instrumental": "true"}, "instrumental"))
        self.assertFalse(runner_io.boolean({"instrumental": "false"}, "instrumental"))
        with self.assertRaises(runner_io.RequestError):
            runner_io.boolean({"instrumental": "yes"}, "instrumental")
        self.assertEqual(runner_io.choice({"mode": "edit"}, "mode", ("edit", "inpaint")), "edit")
        with self.assertRaisesRegex(runner_io.RequestError, "mode must be one of"):
            runner_io.choice({"mode": "erase"}, "mode", ("edit", "inpaint"))

    def test_unexpected_inputs_are_refused(self) -> None:
        runner_io.only({"prompt": "x", "seed": "1"}, {"prompt", "seed", "model"})
        with self.assertRaisesRegex(runner_io.RequestError, "unexpected input: extra"):
            runner_io.only({"prompt": "x", "extra": "1"}, {"prompt"})


class OutputTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_writes_the_result_manifest_the_host_validates(self) -> None:
        runner_io.write_result(
            self.temp.path,
            [runner_io.Artifact("video.mp4", "video/mp4"), runner_io.Artifact("poster.jpg", "image/jpeg", poster_for="video.mp4")],
            metadata={"seed": 7},
        )
        self.assertEqual(
            json.loads((self.temp.path / "result.json").read_text()),
            {
                "schema_version": 1,
                "artifacts": [
                    {"file": "video.mp4", "contentType": "video/mp4"},
                    {"file": "poster.jpg", "contentType": "image/jpeg", "role": "poster", "posterFor": "video.mp4"},
                ],
                "metadata": {"seed": 7},
            },
        )

    def test_an_artifact_may_carry_its_object_path(self) -> None:
        self.assertEqual(
            runner_io.Artifact("decisions.json", "application/json", object_path="open-jev/decisions.json").to_json(),
            {"file": "decisions.json", "contentType": "application/json", "objectPath": "open-jev/decisions.json"},
        )

    def test_writes_a_failure_code(self) -> None:
        runner_io.write_failure(self.temp.path, "classification_request_rejected")
        self.assertEqual(
            json.loads((self.temp.path / "failure.json").read_text()),
            {"errorCode": "classification_request_rejected"},
        )

    def test_plan_outputs_go_to_the_github_output_file(self) -> None:
        output = self.temp.path / "github_output"
        runner_io.write_github_output(str(output), {"profile": "z-image-turbo"})
        self.assertEqual(output.read_text(), "profile=z-image-turbo\n")


if __name__ == "__main__":
    unittest.main()
