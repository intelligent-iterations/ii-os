"""ltx-video image-to-video: request validation, the LTX-2.3 ComfyUI graph (with
and without the optional abliterated Gemma LoRA), the poster frame, prompt
redaction in diagnostics, models.json and the workflow's contract."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import types
import unittest
from unittest import mock

from tests.support import KIT_ROOT, RUNNERS, TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
runner_entry = load("runners/common/runner_entry.py", "runner_entry")
task = load("runners/ltx-video/tasks/image_to_video.py", "kit_ltx_video_image_to_video")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

RUNNER = RUNNERS / "ltx-video"
WORKFLOW = KIT_ROOT / ".github" / "workflows" / "ltx-image-to-video.yml"
LORA = "loras/gemma-3-12b-it-abliterated_lora_rank64_bf16.safetensors"
PROMPT = "a paper boat drifts down a rain gutter"


def image_source(path: str = "/work/in/sources/00.png", content_type: str = "image/png", kind: str = "image") -> runner_io.Source:
    return runner_io.Source(path=Path(path), content_type=content_type, kind=kind, ordinal=0, role=None, size_bytes=10)


def request(sources: list | None = None, **inputs: str) -> runner_io.Request:
    values = {"source_asset_id": "asset-1", "prompt": PROMPT, "duration_seconds": "5", "orientation": "landscape", "fps": "24"}
    values.update(inputs)
    return runner_io.Request(inputs=values, sources=[image_source()] if sources is None else sources)


def nodes(graph: dict, class_type: str) -> list[dict]:
    return [node for node in graph.values() if node["class_type"] == class_type]


def links(graph: dict) -> list[tuple[str, str, list]]:
    found = []
    for node_id, node in graph.items():
        for name, value in node["inputs"].items():
            if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str):
                found.append((node_id, name, value))
    return found


def build(lora: bool, **inputs: str) -> dict:
    return task.graph(task.plan(request(**inputs)), image="source.png", abliterated_lora=lora)


class PlanTest(unittest.TestCase):
    def test_a_request_maps_to_the_ltx_profile(self) -> None:
        plan = task.plan(request())
        self.assertEqual(plan["profile"], "ltx-2.3")
        self.assertEqual((plan["duration_seconds"], plan["fps"], plan["source_suffix"]), (5, 24, ".png"))

    def test_orientation_picks_a_720p_frame(self) -> None:
        self.assertEqual(task.plan(request(orientation="landscape"))["size"], [1280, 720])
        self.assertEqual(task.plan(request(orientation="portrait"))["size"], [720, 1280])
        for bad in ("square", ""):
            with self.subTest(orientation=bad), self.assertRaisesRegex(runner_io.RequestError, "orientation"):
                task.plan(request(orientation=bad))

    def test_duration_is_two_to_twenty_whole_seconds_defaulting_to_five(self) -> None:
        self.assertEqual(task.plan(request(duration_seconds=""))["duration_seconds"], 5)
        self.assertEqual(task.plan(request(duration_seconds="20.0"))["duration_seconds"], 20)
        for bad in ("1", "21", "2.5", "five"):
            with self.subTest(duration=bad), self.assertRaisesRegex(runner_io.RequestError, "duration_seconds"):
                task.plan(request(duration_seconds=bad))

    def test_fps_is_a_required_whole_number_from_12_to_60(self) -> None:
        self.assertEqual(task.plan(request(fps="60"))["fps"], 60)
        for bad in ("", "11", "61", "23.976"):
            with self.subTest(fps=bad), self.assertRaisesRegex(runner_io.RequestError, "fps"):
                task.plan(request(fps=bad))

    def test_the_prompt_is_required_and_bounded_without_being_echoed(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt="  "))
        with self.assertRaises(runner_io.RequestError) as caught:
            task.plan(request(prompt="secret words " * 700))
        self.assertIn("prompt", str(caught.exception))
        self.assertNotIn("secret words", str(caught.exception))

    def test_the_seed_is_random_and_positive(self) -> None:
        self.assertGreater(task.plan(request())["seed"], 0)

    def test_inputs_the_catalog_does_not_declare_are_refused(self) -> None:
        for name in ("seed", "prompt_enhance", "model"):
            with self.subTest(name=name), self.assertRaisesRegex(runner_io.RequestError, name):
                task.plan(request(**{name: "1"}))

    def test_exactly_one_png_jpeg_or_webp_source_image(self) -> None:
        for content_type, suffix in (("image/jpeg", ".jpg"), ("image/webp", ".webp")):
            source = image_source(f"/work/in/sources/00{suffix}", content_type)
            self.assertEqual(task.plan(request(sources=[source]))["source_suffix"], suffix)
        refused = {
            "none": [],
            "two": [image_source(), image_source("/work/in/sources/01.png")],
            "video": [image_source("/work/in/sources/00.mp4", "video/mp4", "video")],
            "gif": [image_source("/work/in/sources/00.gif", "image/gif")],
        }
        for label, sources in refused.items():
            with self.subTest(case=label), self.assertRaisesRegex(runner_io.RequestError, "source"):
                task.plan(request(sources=sources))


class GraphTest(unittest.TestCase):
    def test_the_graph_carries_the_request(self) -> None:
        plan = task.plan(request(orientation="portrait", duration_seconds="8", fps="30", prompt="a heron lifts off"))
        graph = task.graph(plan, image="source.webp", abliterated_lora=False)
        self.assertEqual(nodes(graph, "LoadImage")[0]["inputs"]["image"], "source.webp")
        self.assertEqual(graph["320:312"]["inputs"]["value"], 720)
        self.assertEqual(graph["320:299"]["inputs"]["value"], 1280)
        self.assertEqual(graph["320:301"]["inputs"]["value"], 8)
        self.assertEqual(graph["320:300"]["inputs"]["value"], 30)
        self.assertEqual(nodes(graph, "PrimitiveStringMultiline")[0]["inputs"]["value"], "a heron lifts off")
        self.assertEqual(graph["320:277"]["inputs"]["noise_seed"], plan["seed"])
        self.assertEqual(graph["320:276"]["inputs"]["noise_seed"], plan["seed"] + 1)
        self.assertIs(graph["320:328"]["inputs"]["value"], False)
        self.assertEqual(nodes(graph, "SaveVideo")[0]["inputs"]["filename_prefix"], "ii-os/video")

    def test_without_the_abliterated_lora_the_prompt_enhancer_reads_the_text_encoder(self) -> None:
        graph = build(lora=False)
        self.assertEqual(nodes(graph, "LoraLoader"), [])
        self.assertEqual(nodes(graph, "TextGenerateLTX2Prompt")[0]["inputs"]["clip"], ["320:317", 0])

    def test_with_the_abliterated_lora_the_prompt_enhancer_reads_it(self) -> None:
        graph = build(lora=True)
        lora = nodes(graph, "LoraLoader")
        self.assertEqual([node["inputs"]["lora_name"] for node in lora], [LORA.split("/", 1)[1]])
        self.assertEqual(nodes(graph, "TextGenerateLTX2Prompt")[0]["inputs"]["clip"], ["320:324", 1])

    def test_the_user_prompt_reaches_the_text_encoder_verbatim(self) -> None:
        # ii-os passes creative text as written; the template's LLM prompt
        # enhancer stays switched off in both graph variants.
        for lora in (False, True):
            graph = build(lora=lora, prompt="exact words")
            with self.subTest(lora=lora):
                self.assertIs(graph["320:328"]["inputs"]["value"], False)
                switch = graph[graph["320:303"]["inputs"]["text"][0]]
                self.assertEqual(switch["class_type"], "ComfySwitchNode")
                self.assertEqual(switch["inputs"]["switch"], ["320:328", 0])
                self.assertEqual(graph[switch["inputs"]["on_false"][0]]["inputs"]["value"], "exact words")
        self.assertFalse(hasattr(task, "prompt_enhance"))

    def test_every_link_resolves_and_nothing_echoes_the_prompt_into_history(self) -> None:
        for lora in (False, True):
            graph = build(lora=lora)
            with self.subTest(lora=lora):
                for node_id, name, (target, _) in links(graph):
                    self.assertIn(target, graph, f"{node_id}.{name}")
                self.assertEqual(nodes(graph, "PreviewAny"), [])
                json.dumps(graph)

    def test_every_model_file_a_graph_loads_is_in_the_profile(self) -> None:
        manifest = models.load_manifest(RUNNER / "models.json")
        profile = set(manifest.profiles["ltx-2.3"])
        loaders = {
            ("CheckpointLoaderSimple", "ckpt_name"): "checkpoints",
            ("LTXVAudioVAELoader", "ckpt_name"): "checkpoints",
            ("LTXAVTextEncoderLoader", "ckpt_name"): "checkpoints",
            ("LTXAVTextEncoderLoader", "text_encoder"): "text_encoders",
            ("LatentUpscaleModelLoader", "model_name"): "latent_upscale_models",
            ("LoraLoaderModelOnly", "lora_name"): "loras",
            ("LoraLoader", "lora_name"): "loras",
        }
        used = set()
        for node in build(lora=True).values():
            for (class_type, field), folder in loaders.items():
                if node["class_type"] == class_type:
                    used.add(f"{folder}/{node['inputs'][field]}")
        self.assertEqual(used, profile)
        self.assertEqual(task.ABLITERATED_LORA, LORA)

    def test_building_a_graph_leaves_the_template_untouched(self) -> None:
        first = build(lora=False, prompt="one")
        second = build(lora=True, prompt="two")
        self.assertIn("320:324", second)
        self.assertNotIn("320:324", first)
        template = json.loads((RUNNER / "graphs" / "image_to_video.json").read_text(encoding="utf-8"))
        self.assertEqual(template["320:319"]["inputs"]["value"], "")


class ModelsTest(unittest.TestCase):
    def test_every_file_is_pinned_and_licensed(self) -> None:
        manifest = models.load_manifest(RUNNER / "models.json")
        self.assertEqual(manifest.runner, "ltx-video")
        self.assertEqual(sorted(manifest.profiles), ["ltx-2.3"])
        for item in manifest.files.values():
            with self.subTest(path=item.path):
                self.assertIsNotNone(item.size_bytes)
                self.assertIsNotNone(item.sha256)
                self.assertRegex(item.source, r"^https://huggingface\.co/[^/]+/[^/]+/resolve/[0-9a-f]{40}/")
                self.assertTrue(item.license)

    def test_only_the_abliterated_lora_is_optional_and_it_says_why(self) -> None:
        manifest = models.load_manifest(RUNNER / "models.json")
        self.assertEqual([path for path, item in manifest.files.items() if item.optional], [LORA])
        lora = manifest.files[LORA]
        self.assertEqual(lora.license, "unstated")
        self.assertIn("optional", lora.note.lower())
        for item in manifest.files.values():
            if "LTX" in item.license:
                self.assertIn("10,000,000", item.note)


class FakeServer:
    """Stands in for comfyui_runtime.ComfyServer: records the graph, writes a video."""

    instances: list["FakeServer"] = []
    failure: str | None = None

    def __init__(self, *, models_dir: Path, scratch_dir: Path, extra_args: tuple = (), **_: object):
        self.models_dir, self.scratch, self.extra_args = models_dir, scratch_dir, tuple(extra_args)
        self.output_dir = scratch_dir / "output"
        self.input_dir = scratch_dir / "input"
        self.staged: list[str] = []
        self.graph: dict | None = None
        FakeServer.instances.append(self)

    def __enter__(self) -> "FakeServer":
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.input_dir.mkdir(parents=True, exist_ok=True)
        return self

    def __exit__(self, *exc: object) -> None:
        return None

    def stage_input(self, source: Path, name: str) -> str:
        (self.input_dir / name).write_bytes(source.read_bytes())
        self.staged.append(name)
        return name

    def run(self, graph: dict, *, timeout: int) -> dict:
        self.graph, self.timeout = graph, timeout
        if FakeServer.failure is not None:
            raise RuntimeError(FakeServer.failure)
        (self.output_dir / "video").mkdir(exist_ok=True)
        (self.output_dir / "video" / "ii-os_00001_.mp4").write_bytes(b"\x00\x00\x00\x18ftypisom" + b"\x00" * 32)
        return {"outputs": {"75": {"images": [{"filename": "ii-os_00001_.mp4", "subfolder": "video", "type": "output"}]}}}


def fake_output_files(history: dict, output_dir: Path, suffixes: tuple) -> list[Path]:
    item = history["outputs"]["75"]["images"][0]
    path = output_dir / item["subfolder"] / item["filename"]
    return [path] if path.suffix in suffixes else []


def ffmpeg_writing(content: bytes, returncode: int = 0):
    def fake(command: list[str], **_: object) -> subprocess.CompletedProcess:
        Path(command[-1]).write_bytes(content)
        return subprocess.CompletedProcess(command, returncode)
    return fake


PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        root = self.temp.path
        for child in ("in/sources", "out", "models/checkpoints", "scratch"):
            (root / child).mkdir(parents=True)
        (root / "in" / "sources" / "00.jpg").write_bytes(b"\xff\xd8\xff\xe0 synthetic")
        self.request = request(sources=[image_source(str(root / "in" / "sources" / "00.jpg"), "image/jpeg")])
        self.context = runner_entry.RunContext(root / "models", root / "out", root / "scratch", {})
        FakeServer.instances, FakeServer.failure = [], None
        runtime = types.ModuleType("comfyui_runtime")
        runtime.ComfyServer, runtime.output_files = FakeServer, fake_output_files
        self.modules = mock.patch.dict(sys.modules, {"comfyui_runtime": runtime})
        self.modules.start()

    def tearDown(self) -> None:
        self.modules.stop()
        self.temp.cleanup()

    def run_task(self, ffmpeg=ffmpeg_writing(PNG)) -> tuple[list, dict, str]:
        output = io.StringIO()
        with mock.patch.object(task.subprocess, "run", side_effect=ffmpeg), contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            artifacts, metadata = task.run(task.plan(self.request), self.request, self.context)
        return artifacts, metadata, output.getvalue()

    def test_a_run_writes_the_video_and_its_opening_frame_as_a_poster(self) -> None:
        artifacts, metadata, output = self.run_task()
        poster = {"file": "poster.png", "contentType": "image/png", "role": "poster", "posterFor": "video.mp4"}
        self.assertEqual([item.to_json() for item in artifacts], [{"file": "video.mp4", "contentType": "video/mp4"}, poster])
        self.assertTrue((self.context.output_dir / "video.mp4").read_bytes()[4:8] == b"ftyp")
        server = FakeServer.instances[0]
        self.assertEqual(server.staged, ["source.jpg"])
        self.assertIn("--disable-metadata", server.extra_args)
        self.assertEqual(nodes(server.graph, "LoadImage")[0]["inputs"]["image"], "source.jpg")
        self.assertEqual(nodes(server.graph, "LoraLoader"), [])
        self.assertLessEqual(server.timeout, 100 * 60)
        self.assertEqual(metadata["orientation"], "landscape")
        self.assertNotIn(PROMPT, json.dumps(metadata) + output)

    def test_the_abliterated_lora_is_wired_in_only_when_the_model_folder_has_it(self) -> None:
        lora = self.context.models_dir / LORA
        lora.parent.mkdir(parents=True)
        lora.write_bytes(b"synthetic")
        self.run_task()
        self.assertEqual(len(nodes(FakeServer.instances[0].graph, "LoraLoader")), 1)

    def test_a_poster_that_cannot_be_made_leaves_the_video_alone(self) -> None:
        failures = {
            "exit code": ffmpeg_writing(PNG, returncode=1),
            "not a png": ffmpeg_writing(b"GIF89a"),
            "no ffmpeg": FileNotFoundError("ffmpeg"),
        }
        for label, ffmpeg in failures.items():
            with self.subTest(case=label):
                artifacts, _, _ = self.run_task(ffmpeg)
                self.assertEqual([item.file for item in artifacts], ["video.mp4"])
                self.assertFalse((self.context.output_dir / "poster.png").exists())

    def test_comfyui_errors_never_carry_the_prompt(self) -> None:
        escaped = json.dumps(PROMPT)[1:-1]
        FakeServer.failure = 'ComfyUI generation failed: {"current_inputs": {"text": ["' + escaped + '"]}, "x": "' + escaped[:9]
        with self.assertRaises(RuntimeError) as caught:
            self.run_task()
        message = str(caught.exception)
        self.assertIn("ComfyUI generation failed", message)
        self.assertNotIn(PROMPT, message)
        self.assertFalse(message.endswith(escaped[:9]))
        self.assertIsNone(caught.exception.__cause__)
        self.assertTrue(caught.exception.__suppress_context__)


class RedactTest(unittest.TestCase):
    def test_full_escaped_and_truncated_copies_are_removed(self) -> None:
        prompt = 'say "hi" - then wave'
        escaped = json.dumps(prompt)[1:-1]
        self.assertEqual(task.redact(f"a {prompt} b", prompt), "a [prompt] b")
        self.assertEqual(task.redact(f"a {escaped} b", prompt), "a [prompt] b")
        self.assertEqual(task.redact(f"cut at {escaped[:6]}", prompt), "cut at [prompt]")
        self.assertEqual(task.redact("nothing here", prompt), "nothing here")


class WorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WORKFLOW.read_text(encoding="utf-8")

    def test_it_declares_every_catalog_input_as_an_optional_string(self) -> None:
        for name in ("ii_request_id", "ii_payload_mode", "source_asset_id", "prompt", "duration_seconds", "orientation", "fps"):
            with self.subTest(input=name):
                self.assertRegex(self.text, rf"\n      {name}:\n        description: [^\n]+\n        required: (true|false)\n        type: string\n")
        self.assertNotIn("prompt_enhance", self.text)
        self.assertNotIn("\n      seed:", self.text)

    def test_it_runs_the_ltx_video_runner_on_a_gpu_with_one_image_source(self) -> None:
        for expected in (
            "RUNNER_NAME: ltx-video\n",
            "RUNNER_TASK: image-to-video\n",
            "--runner-image II_OS_RUNNER_IMAGE_LTX_VIDEO",
            "RUNNER_IMAGE: ${{ vars.II_OS_RUNNER_IMAGE_LTX_VIDEO }}",
            'max-sources: "1"',
            "source-kinds: image\n",
            ' --gpu\n',
            "allowed-content-types: video/mp4,image/png\n",
            'max-bytes: "2147483648"',
            "group: ii-os-image-to-video-${{ inputs.ii_request_id }}",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.text)

    def test_it_reports_video_error_codes_and_has_a_two_hour_generate_job(self) -> None:
        self.assertEqual(self.text.count("error-code: video_generation_failed"), 2)
        self.assertEqual(self.text.count("cancelled-error-code: video_generation_cancelled"), 2)
        self.assertNotRegex(self.text, r"image_generation_|ltx_workflow_")
        self.assertRegex(self.text, r"\n  generate:\n(?:    .*\n)*?    timeout-minutes: 120\n")


class RunnerFolderTest(unittest.TestCase):
    def test_the_image_runs_this_task_by_default(self) -> None:
        dockerfile = (RUNNER / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn('ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/ltx-video/entrypoint.py"]', dockerfile)
        self.assertIn('CMD ["run", "--task", "image-to-video"]', dockerfile)
        self.assertRegex(dockerfile, r"\nFROM [^\s@]+@sha256:[0-9a-f]{64}\n")
        for revision in re.findall(r"_REVISION=(\S+)", dockerfile):
            self.assertRegex(revision, r"^[0-9a-f]{40}$")

    def test_dependencies_come_only_from_the_runner_locks(self) -> None:
        names = sorted(path.name for path in RUNNER.rglob("*") if path.is_file() and path.name.startswith("requirements"))
        self.assertEqual(names, ["requirements-build.lock.txt", "requirements.in", "requirements.lock.txt"])
        lock = (RUNNER / "requirements.lock.txt").read_text(encoding="utf-8")
        # ComfyUI-LTXVideo at its revision imports `pad`, which kornia 0.8.3 removed.
        self.assertRegex(lock, r"\nkornia==0\.8\.2 \\\n")
        dockerfile = (RUNNER / "Dockerfile").read_text(encoding="utf-8")
        self.assertNotIn("requirements.txt", dockerfile)


if __name__ == "__main__":
    unittest.main()
