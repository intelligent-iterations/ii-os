"""media-render: run a video-editor export the dashboard already compiled.

The editor compiles a timeline into one FFmpeg invocation before dispatch; the
runner only puts every file that invocation names where it expects it and
hands the manifest to the same renderer the browser uses."""

from __future__ import annotations

import json
from pathlib import Path
import unittest

from tests.support import TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
task = load("runners/media-render/tasks/editor_render.py", "kit_media_render_editor_render")


def manifest(**overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "version": 1,
        "arguments": ["-i", "input-0.mp4", "-i", "input-1.m4a", "-f", "mp4", "output.mp4"],
        "outputName": "output.mp4",
        "mediaType": "video/mp4",
        "expectedDurationMicros": 2_000_000,
        "maxOutputBytes": 64 * 1024 * 1024,
        "inputs": [
            {"name": "input-0.mp4", "assetId": "asset-1", "byteLength": 64},
            {"name": "input-1.m4a", "assetId": "asset-2", "byteLength": 32},
        ],
    }
    value.update(overrides)
    return value


def sources(root: Path) -> list[runner_io.Source]:
    return [
        runner_io.Source(root / "sources/00.mp4", "video/mp4", "video", 0, "input-0.mp4", 64, "asset-1"),
        runner_io.Source(root / "sources/01.m4a", "audio/mp4", "audio", 1, "input-1.m4a", 32, "asset-2"),
    ]


def request(root: Path, value: object = None, staged: list[runner_io.Source] | None = None) -> runner_io.Request:
    text = value if isinstance(value, str) else json.dumps(manifest() if value is None else value)
    return runner_io.Request({"render_manifest": text}, sources(root) if staged is None else staged)


class PlanTest(unittest.TestCase):
    root = Path("/work/in")

    def test_accepts_a_render_this_runner_will_execute(self) -> None:
        plan = task.plan(request(self.root))
        self.assertEqual(plan["profile"], "ffmpeg")
        self.assertEqual(plan["output_name"], "output.mp4")
        self.assertEqual(plan["media_type"], "video/mp4")
        self.assertEqual([item["name"] for item in plan["inputs"]], ["input-0.mp4", "input-1.m4a"])

    def test_refuses_what_the_manifest_cannot_promise(self) -> None:
        cases = {
            "another version": manifest(version=2),
            "no arguments": manifest(arguments=[]),
            "non-text argument": manifest(arguments=["-i", 3]),
            "unnamed output": manifest(outputName="../output.mp4"),
            "an output type ii-os does not store": manifest(outputName="output.mov", mediaType="video/quicktime"),
            "name and type disagree": manifest(outputName="output.webm"),
            "output bound out of range": manifest(maxOutputBytes=0),
            "reads nothing": manifest(inputs=[]),
            "more files than it fetches": manifest(inputs=[{"name": f"input-{i}.mp4", "assetId": f"a{i}"} for i in range(13)]),
        }
        for label, value in cases.items():
            with self.subTest(label), self.assertRaises(runner_io.RequestError):
                task.plan(request(self.root, value))

    def test_refuses_a_manifest_that_is_not_json_or_too_large(self) -> None:
        for value in ("{not json", "x" * 60001):
            with self.subTest(size=len(value)), self.assertRaises(runner_io.RequestError):
                task.plan(request(self.root, value))

    def test_every_named_input_must_be_the_staged_asset_it_was_built_against(self) -> None:
        staged = sources(self.root)
        cases = {
            "missing": staged[:1],
            "extra": staged + [runner_io.Source(self.root / "sources/02.png", "image/png", "image", 2, "input-2.png", 5, "asset-3")],
            "another asset": [staged[0], runner_io.Source(staged[1].path, "audio/mp4", "audio", 1, "input-1.m4a", 32, "asset-9")],
            "wrong size": [staged[0], runner_io.Source(staged[1].path, "audio/mp4", "audio", 1, "input-1.m4a", 33, "asset-2")],
            "out of order": list(reversed(staged)),
        }
        for label, value in cases.items():
            with self.subTest(label), self.assertRaises(runner_io.RequestError):
                task.plan(request(self.root, staged=value))

    def test_refuses_inputs_the_render_does_not_declare(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "unexpected input"):
            task.plan(runner_io.Request({"render_manifest": json.dumps(manifest()), "prompt": "x"}, sources(self.root)))


class RunPreparationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        (self.temp.path / "in" / "sources").mkdir(parents=True)
        for item in sources(self.temp.path / "in"):
            item.path.write_bytes(b"x" * item.size_bytes)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_inputs_appear_under_the_names_the_arguments_use(self) -> None:
        plan = task.plan(request(self.temp.path / "in"))
        directory = task.prepare_inputs(plan, self.temp.path / "scratch")
        self.assertEqual(sorted(path.name for path in directory.iterdir()), ["input-0.mp4", "input-1.m4a"])
        self.assertEqual((directory / "input-0.mp4").read_bytes(), b"x" * 64)

    def test_the_render_runs_the_exported_tool_offline(self) -> None:
        plan = task.plan(request(self.temp.path / "in"))
        command, env = task.render_command(
            plan,
            manifest_file=Path("/tmp/render.json"),
            input_dir=Path("/tmp/render-inputs"),
            output=Path("/work/out/output.mp4"),
        )
        self.assertEqual(command[0], "flutter")
        self.assertIn("--no-pub", command)
        self.assertEqual(command[-1], "tool/render_editor_manifest.dart")
        self.assertEqual(env["II_RENDER_OUTPUT"], "/work/out/output.mp4")
        self.assertEqual(env["II_RENDER_INPUT_DIR"], "/tmp/render-inputs")
        self.assertEqual(env["FLUTTER_SUPPRESS_ANALYTICS"], "true")


if __name__ == "__main__":
    unittest.main()
