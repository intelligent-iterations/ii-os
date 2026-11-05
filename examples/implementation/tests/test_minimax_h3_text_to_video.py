"""minimax-h3 text-to-video (catalog id text-to-video-minimax-h3): request
validation for every generation mode, the isolated render with its reference
checks, prompt redaction, the workflow wiring, the image and its hashed lock,
and models.json."""

from __future__ import annotations

import contextlib
import dataclasses
import io
import json
from pathlib import Path
import re
import sys
import types
import unittest
from unittest import mock

from tests.support import KIT_ROOT, RUNNERS, TempDir, load

RUNNER = RUNNERS / "minimax-h3"
if str(RUNNER) not in sys.path:
    sys.path.insert(0, str(RUNNER))

runner_io = load("runners/common/runner_io.py", "runner_io")
runner_entry = load("runners/common/runner_entry.py", "runner_entry")
task = load("runners/minimax-h3/tasks/text_to_video.py", "kit_minimax_h3_text_to_video")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

from minimax_h3 import profiles  # noqa: E402

WORKFLOW = KIT_ROOT / ".github" / "workflows" / "minimax-h3-text-to-video.yml"
PROMPT = "a paper lantern drifts over a quiet harbor at dusk"
CATALOG_INPUTS = (
    "prompt", "duration_seconds", "orientation", "fps", "performance_mode", "generation_mode",
    "reference_manifest", "edit_operation", "identity_replacement_consent",
)
SUFFIX = {"image": "png", "video": "mp4", "audio": "wav"}
TYPES = {"image": "image/png", "video": "video/mp4", "audio": "audio/wav"}


def asset(index: int) -> str:
    return f"00000000-0000-4000-8000-{index:012d}"


def request(refs: tuple = (), root: Path = Path("/work/in"), **inputs: str) -> runner_io.Request:
    mode = inputs.get("generation_mode", "text_to_video")
    values = {"prompt": PROMPT, "duration_seconds": "15", "orientation": "landscape", "fps": "24",
              "performance_mode": "quality", "generation_mode": mode}
    if refs:
        manifest = {"schema_version": 1, "mode": mode, "references": [
            {"asset_id": asset(i), "kind": kind, "role": role, "ordinal": i} for i, (kind, role) in enumerate(refs)]}
        if mode == "video_edit":
            manifest.update(edit_operation="general_edit", identity_replacement_consent=False)
        values["reference_manifest"] = json.dumps(manifest)
    values.update(inputs)
    sources = [
        runner_io.Source(root / "sources" / f"{i:02d}.{SUFFIX[kind]}", TYPES[kind], kind, i, role, 10, asset(i))
        for i, (kind, role) in enumerate(refs)
    ]
    return runner_io.Request(inputs={k: v for k, v in values.items() if v is not None}, sources=sources)


class PlanTest(unittest.TestCase):
    def test_text_to_video_quality_plans_the_fl2va_profile(self) -> None:
        plan = task.plan(request())
        self.assertEqual(plan["profile"], "fl2va")
        self.assertEqual((plan["performance_mode"], plan["generation_mode"]), ("quality", "text_to_video"))
        self.assertEqual((plan["source_size"], plan["delivery_size"]), ((1280, 736), (1280, 720)))
        self.assertEqual((plan["duration_seconds"], plan["frames"], plan["fps"]), (15, 362, 24))
        self.assertEqual(plan["prompt"], "integrated_multimodal_description: " + PROMPT)
        self.assertIsInstance(plan["seed"], int)

    def test_orientation_turbo_and_reference_modes_pick_canvas_and_profile(self) -> None:
        portrait = task.plan(request(orientation="portrait", duration_seconds="4"))
        self.assertEqual((portrait["source_size"], portrait["delivery_size"], portrait["frames"]), ((736, 1280), (720, 1280), 107))
        self.assertEqual(task.plan(request(performance_mode="turbo"))["profile"], "fl2va-turbo")
        refs = (("video", "source_video"), ("image", "subject"))
        plan = task.plan(request(refs, generation_mode="video_continue"))
        self.assertEqual(plan["profile"], "ref2va")
        self.assertTrue(plan["prompt"].startswith("subject_definitions:\n<Video 1>"))

    def test_older_catalogs_without_mode_inputs_get_the_defaults(self) -> None:
        plan = task.plan(request(performance_mode=None, generation_mode=None))
        self.assertEqual((plan["performance_mode"], plan["generation_mode"]), ("quality", "text_to_video"))

    def test_requests_outside_the_contract_are_refused(self) -> None:
        cases = {
            "unexpected input": {"seed": "4"},
            "long prompt": {"prompt": "x" * 7001},
            "empty prompt": {"prompt": " "},
            "short": {"duration_seconds": "3"},
            "long": {"duration_seconds": "16"},
            "fractional": {"duration_seconds": "5.5"},
            "fps": {"fps": "30"},
            "orientation": {"orientation": "square"},
            "performance": {"performance_mode": "fast"},
            "mode": {"generation_mode": "image_to_audio"},
            "chained extension": {"extension_method": "chained"},
        }
        for label, inputs in cases.items():
            with self.subTest(case=label), self.assertRaises(runner_io.RequestError):
                task.plan(request(**inputs))

    def test_turbo_serves_only_the_endpoint_modes(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "Turbo"):
            task.plan(request((("video", "source_video"),), generation_mode="video_continue", performance_mode="turbo"))
        task.plan(request((("image", "first_frame"),), generation_mode="first_frame_to_video", performance_mode="turbo"))

    def test_a_continuation_may_name_the_single_pass_method(self) -> None:
        task.plan(request((("video", "source_video"),), generation_mode="video_continue", extension_method="single_pass"))

    def test_staged_sources_must_be_the_manifest(self) -> None:
        req = request((("image", "first_frame"),), generation_mode="first_frame_to_video")
        mismatched = runner_io.Request(req.inputs, [dataclasses.replace(req.sources[0], role="subject")])
        with self.assertRaises(runner_io.RequestError) as caught:
            task.plan(mismatched)
        self.assertEqual(caught.exception.code, task.REFERENCE_REJECTED)

    def test_the_plan_step_logs_only_the_profile(self) -> None:
        temp = TempDir()
        try:
            (temp.path / "inputs.json").write_text(json.dumps(request().inputs), encoding="utf-8")
            printed = io.StringIO()
            with contextlib.redirect_stdout(printed):
                status = runner_entry.main(["plan", "--task", "text-to-video", "--input-dir", str(temp.path)], {"text-to-video": task.__name__})
            self.assertEqual(status, 0)
            self.assertEqual(json.loads(printed.getvalue()), {"task": "text-to-video", "profile": "fl2va"})
        finally:
            temp.cleanup()


SAGE_LOG = "Using sage attention\nFound comfy_kitchen backend cuda: {'available': True, 'disabled': False, 'capabilities': []}\n"


class FakeServer:
    """Stands in for comfyui_runtime.ComfyServer: records what the task asked of it."""

    instances: list["FakeServer"] = []
    failure: str | None = None
    log = SAGE_LOG

    def __init__(self, *, models_dir: Path, scratch_dir: Path, reserve_vram_gb: float = 1.0, extra_args: tuple = (), **_: object):
        self.scratch, self.reserve_vram_gb, self.extra_args = scratch_dir, reserve_vram_gb, tuple(extra_args)
        self.output_dir, self.input_dir = scratch_dir / "output", scratch_dir / "input"
        self.staged: list[str] = []
        self.graph: dict | None = None
        FakeServer.instances.append(self)

    def __enter__(self) -> "FakeServer":
        for folder in (self.output_dir, self.input_dir):
            folder.mkdir(parents=True, exist_ok=True)
        (self.scratch / "comfyui.log").write_text(FakeServer.log, encoding="utf-8")
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
        (self.output_dir / "ii-os").mkdir(exist_ok=True)
        (self.output_dir / "ii-os" / "raw_00001_.mp4").write_bytes(b"raw render")
        return {"outputs": {"14": {"images": [{"filename": "raw_00001_.mp4", "subfolder": "ii-os", "type": "output"}]}}}


def fake_output_files(history: dict, output_dir: Path, suffixes: tuple) -> list[Path]:
    item = history["outputs"]["14"]["images"][0]
    return [output_dir / item["subfolder"] / item["filename"]]


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        root = self.temp.path
        for child in ("in/sources", "out", "models", "scratch"):
            (root / child).mkdir(parents=True)
        self.context = runner_entry.RunContext(root / "models", root / "out", root / "scratch", {})
        FakeServer.instances, FakeServer.failure, FakeServer.log = [], None, SAGE_LOG
        self.durations: dict[str, float] = {}
        runtime = types.ModuleType("comfyui_runtime")
        runtime.ComfyServer, runtime.output_files = FakeServer, fake_output_files
        self.patches = [
            mock.patch.dict(sys.modules, {"comfyui_runtime": runtime}),
            mock.patch.object(task, "installed_version", return_value=profiles.SAGEATTENTION_VERSION),
            mock.patch.object(task.media, "probe", side_effect=lambda path: {"format": {"duration": str(self.durations[path.name])}, "streams": [{"codec_type": "audio"}]}),
            mock.patch.object(task.media, "finish_video", side_effect=self.finish),
            mock.patch.object(task.media, "write_poster", side_effect=lambda video, poster: poster.write_bytes(b"png") > 0),
        ]
        for patch in self.patches:
            patch.start()

    def tearDown(self) -> None:
        for patch in reversed(self.patches):
            patch.stop()
        self.temp.cleanup()

    def finish(self, raw: Path, final: Path, **kwargs: object) -> dict:
        self.finished = kwargs
        final.write_bytes(raw.read_bytes())
        return {"format": {"duration": "15"}}

    def run_task(self, req: runner_io.Request) -> tuple[list, dict, str]:
        for source in req.sources:
            source.path.write_bytes(b"synthetic " + source.kind.encode())
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed), contextlib.redirect_stderr(printed):
            artifacts, metadata = task.run(task.plan(req), req, self.context)
        return artifacts, metadata, printed.getvalue()

    def test_text_to_video_writes_the_video_and_its_poster(self) -> None:
        artifacts, metadata, printed = self.run_task(request(root=self.temp.path / "in"))
        poster = {"file": "poster.png", "contentType": "image/png", "role": "poster", "posterFor": "video.mp4"}
        self.assertEqual([item.to_json() for item in artifacts], [{"file": "video.mp4", "contentType": "video/mp4"}, poster])
        server = FakeServer.instances[0]
        self.assertEqual(server.extra_args, tuple(task.graph.comfy_args()))
        self.assertEqual(server.reserve_vram_gb, 16.5)
        self.assertEqual(server.timeout, task.GENERATION_TIMEOUT_SECONDS)
        self.assertEqual(server.graph["5"]["inputs"]["prompt"], "integrated_multimodal_description: " + PROMPT)
        self.assertEqual(self.finished, {"width": 1280, "height": 720, "fps": 24, "duration": 15})
        self.assertEqual((metadata["model"], metadata["generation_mode"], metadata["inference_profile"]), ("MiniMax H3", "text_to_video", "native-sage-cab10"))
        self.assertTrue(metadata["comfy_kitchen_cuda"])
        self.assertNotIn(PROMPT, json.dumps(metadata) + printed)

    def test_a_continuation_anchors_the_staged_source(self) -> None:
        req = request((("video", "source_video"), ("audio", "audio_reuse")), root=self.temp.path / "in", generation_mode="video_continue")
        self.durations = {"00.mp4": 5.0, "01.wav": 6.0}
        _, metadata, _ = self.run_task(req)
        server = FakeServer.instances[0]
        self.assertEqual(server.staged, ["ref-00.mp4", "ref-01.wav"])
        guide = next(node for node in server.graph.values() if node["class_type"] == "MiniMaxH3AddGuide")
        load_video = server.graph[guide["inputs"]["image"][0]]["inputs"]["video"][0]
        self.assertEqual(server.graph[load_video]["inputs"]["file"], "ref-00.mp4")
        self.assertEqual(server.graph["5"]["inputs"]["length"], 362)
        self.assertEqual([item["duration_seconds"] for item in metadata["references"]], [5.0, 6.0])

    def test_reference_media_outside_the_model_limits_never_starts_comfyui(self) -> None:
        cases = {
            "too long": ((("video", "motion_reference"),), "reference_to_video", {"00.mp4": 16.0}),
            "totals": ((("audio", "audio_reference"), ("audio", "audio_reuse")), "reference_to_video", {"00.wav": 9.0, "01.wav": 9.0}),
            "adds too little": ((("video", "source_video"),), "video_continue", {"00.mp4": 14.0}),
        }
        for label, (refs, mode, durations) in cases.items():
            with self.subTest(case=label):
                self.durations = durations
                with self.assertRaises(runner_io.RequestError) as caught:
                    self.run_task(request(refs, root=self.temp.path / "in", generation_mode=mode))
                self.assertEqual(caught.exception.code, task.REFERENCE_REJECTED)
                self.assertEqual(FakeServer.instances, [])

    def test_the_image_must_carry_the_pinned_sageattention(self) -> None:
        with mock.patch.object(task, "installed_version", return_value=None), self.assertRaisesRegex(RuntimeError, "SageAttention"):
            self.run_task(request(root=self.temp.path / "in"))
        self.assertEqual(FakeServer.instances, [])

    def test_comfyui_must_confirm_sage_attention_and_the_cuda_kitchen_before_rendering(self) -> None:
        FakeServer.log = "Using pytorch attention\n"
        with self.assertRaisesRegex(RuntimeError, "SageAttention"):
            self.run_task(request(root=self.temp.path / "in"))
        FakeServer.log = "Using sage attention\n"
        with self.assertRaisesRegex(RuntimeError, "comfy-kitchen"):
            self.run_task(request(root=self.temp.path / "in"))
        self.assertTrue(all(server.graph is None for server in FakeServer.instances))
        self.context = dataclasses.replace(self.context, options={"require_comfy_kitchen_cuda": "false"})
        _, metadata, _ = self.run_task(request(root=self.temp.path / "in"))
        self.assertFalse(metadata["comfy_kitchen_cuda"])

    def test_comfyui_errors_never_carry_the_prompt(self) -> None:
        escaped = json.dumps(PROMPT)[1:-1]
        FakeServer.failure = 'ComfyUI generation failed: {"text": "' + escaped + '", "cut": "' + escaped[:12]
        with self.assertRaises(RuntimeError) as caught:
            self.run_task(request(root=self.temp.path / "in"))
        self.assertNotIn(PROMPT, str(caught.exception))
        self.assertFalse(str(caught.exception).endswith(escaped[:12]))
        self.assertIsNone(caught.exception.__cause__)


class WorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WORKFLOW.read_text(encoding="utf-8")

    def test_it_declares_every_input_the_dashboard_may_send_as_an_optional_string(self) -> None:
        for name in ("ii_request_id", "ii_payload_mode", "extension_method", *CATALOG_INPUTS):
            with self.subTest(input=name):
                self.assertRegex(self.text, rf"\n      {name}:\n        description: [^\n]+\n        required: (true|false)\n        type: string\n")

    def test_it_runs_the_minimax_runner_on_a_gpu_with_role_aware_sources(self) -> None:
        for expected in (
            "RUNNER_NAME: minimax-h3\n",
            "RUNNER_TASK: text-to-video\n",
            "--runner-image II_OS_RUNNER_IMAGE_MINIMAX_H3",
            "RUNNER_IMAGE: ${{ vars.II_OS_RUNNER_IMAGE_MINIMAX_H3 }}",
            'max-sources: "12"',
            "source-kinds: image,video,audio\n",
            " --gpu\n",
            "allowed-content-types: video/mp4,image/png\n",
            'max-bytes: "2147483648"',
            "runner-error-codes: minimax_h3_reference_rejected\n",
            "group: ii-os-text-to-video-minimax-h3-${{ inputs.ii_request_id }}",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.text)

    def test_it_reports_minimax_error_codes_and_allows_a_six_hour_render(self) -> None:
        self.assertEqual(self.text.count("error-code: minimax_h3_workflow_failed"), 2)
        self.assertEqual(self.text.count("cancelled-error-code: minimax_h3_workflow_cancelled"), 2)
        self.assertRegex(self.text, r"\n  generate:\n(?:    .*\n)*?    timeout-minutes: 360\n")
        self.assertGreater(360 * 60, task.GENERATION_TIMEOUT_SECONDS + 30 * 60)


class RunnerFolderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dockerfile = (RUNNER / "Dockerfile").read_text(encoding="utf-8")

    def test_the_image_is_pinned_and_runs_this_task_unprivileged(self) -> None:
        self.assertRegex(self.dockerfile, r"\nFROM [^\s@]+@sha256:[0-9a-f]{64}\n")
        self.assertIn(f"ARG COMFYUI_REVISION={task.COMFYUI_REVISION}\n", self.dockerfile)
        self.assertRegex(self.dockerfile, r"\nARG SAGEATTENTION_REVISION=[0-9a-f]{40}\n")
        self.assertIn("COPY runners/minimax-h3/comfy_nodes/ii_os_minimax_h3 /opt/ComfyUI/custom_nodes/ii_os_minimax_h3", self.dockerfile)
        self.assertIn('ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/ii-os-runner/minimax-h3/entrypoint.py"]', self.dockerfile)
        self.assertIn('CMD ["run", "--task", "text-to-video"]', self.dockerfile)
        self.assertIn("\nUSER 65532:65532\n", self.dockerfile)

    def test_every_package_comes_from_the_hashed_lock(self) -> None:
        installs = [line.strip() for line in self.dockerfile.splitlines() if "pip install" in line and not line.lstrip().startswith("#")]
        self.assertEqual(len(installs), 3)
        for command in installs:
            with self.subTest(command=command):
                if re.search(r"-r /opt/ii-os-runner/minimax-h3/requirements(-build)?\.lock\.txt", command):
                    for flag in ("--require-hashes", "--no-deps", "--only-binary :all:"):
                        self.assertIn(flag, command)
                else:
                    # Only the pinned SageAttention checkout is built, against the locked torch.
                    self.assertRegex(command, r"pip install --no-deps --no-build-isolation /tmp/SageAttention \\$")

    def test_the_lock_is_named_so_dependency_scanners_read_it(self) -> None:
        # osv-scanner reads requirements*.txt and skips other names, so a lock
        # called requirements.lock would never be checked for advisories.
        locks = sorted(path.name for path in RUNNER.iterdir() if "lock" in path.name)
        self.assertEqual(locks, ["requirements-build.lock.txt", "requirements.lock.txt"])
        for lock in locks:
            self.assertRegex(lock, r"^requirements[^/]*\.txt$")

    def test_the_lock_pins_every_requirement_with_hashes(self) -> None:
        lock = (RUNNER / "requirements.lock.txt").read_text(encoding="utf-8")
        pinned = dict(re.findall(r"^([A-Za-z0-9_.-]+)==(\S+) \\$", lock, re.M))
        blocks = re.split(r"\n(?=[A-Za-z0-9_.-]+==)", lock.split("\n", 2)[2])
        for block in blocks:
            with self.subTest(package=block.split("==")[0]):
                self.assertRegex(block, r"--hash=sha256:[0-9a-f]{64}")
        wanted = (RUNNER / "requirements.in").read_text(encoding="utf-8")
        for line in wanted.splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            name = re.split(r"[<>=~!\[ ]", line.strip())[0].lower().replace("_", "-")
            with self.subTest(requirement=name):
                self.assertIn(name, {key.lower() for key in pinned})
                exact = re.search(r"==(\S+)$", line.strip())
                if exact:
                    self.assertEqual(pinned[next(key for key in pinned if key.lower() == name)], exact.group(1))


class ModelsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = models.load_manifest(RUNNER / "models.json")

    def test_three_profiles_cover_the_two_transformers_and_the_turbo_adapter(self) -> None:
        self.assertEqual(self.manifest.runner, "minimax-h3")
        shared = {f"text_encoders/{profiles.TEXT_ENCODER}", f"vae/{profiles.VIDEO_VAE}", f"vae/{profiles.AUDIO_VAE}"}
        self.assertEqual(set(self.manifest.profiles["fl2va"]), shared | {f"diffusion_models/{profiles.FL2VA_MODEL}"})
        self.assertEqual(set(self.manifest.profiles["fl2va-turbo"]), set(self.manifest.profiles["fl2va"]) | {f"loras/{profiles.TURBO_LORA}"})
        self.assertEqual(set(self.manifest.profiles["ref2va"]), shared | {f"diffusion_models/{profiles.REF2VA_MODEL}"})

    def test_every_file_is_pinned_and_states_the_territorial_limits(self) -> None:
        for item in self.manifest.files.values():
            with self.subTest(path=item.path):
                self.assertFalse(item.optional)
                self.assertIsNotNone(item.size_bytes)
                self.assertIsNotNone(item.sha256)
                self.assertRegex(item.source, r"^https://huggingface\.co/[^/]+/[^/]+/resolve/[0-9a-f]{40}/")
                for territory in ("European Union", "United Kingdom", "Republic of Korea", "United States"):
                    self.assertIn(territory, item.note)
        lora = self.manifest.files[f"loras/{profiles.TURBO_LORA}"]
        self.assertIn("Apache-2.0", lora.license)
        self.assertIn("MiniMax H3 Community License", lora.license)

    def test_the_readme_states_the_license_limits_plainly(self) -> None:
        readme = (RUNNER / "README.md").read_text(encoding="utf-8")
        for phrase in ("European Union", "United Kingdom", "Republic of Korea", "United States", "US$20 million", "not licensed"):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, readme)


if __name__ == "__main__":
    unittest.main()
