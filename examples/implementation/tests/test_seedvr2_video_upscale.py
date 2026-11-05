"""seedvr2-video video-upscale: request validation, the SeedVR2 ComfyUI graph and
its out-of-memory fallbacks, the model folder, and the ffprobe/ffmpeg checks."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

from tests.support import KIT_ROOT, RUNNERS, TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
media = load("runners/seedvr2-video/seedvr2_media.py", "seedvr2_media")
task = load("runners/seedvr2-video/tasks/video_upscale.py", "kit_seedvr2_video_upscale")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

RUNNER = RUNNERS / "seedvr2-video"
WORKFLOW = KIT_ROOT / ".github" / "workflows" / "seedvr2-video-upscale.yml"
FP16 = "seedvr2_ema_3b_fp16.safetensors"
FP8 = "seedvr2_ema_3b_fp8_e4m3fn.safetensors"
VAE = "ema_vae_fp16.safetensors"
CATALOG_INPUTS = ("source_asset_id", "target_resolution", "quality_preset", "preserve_audio", "seed")


def source(content_type: str = "video/mp4", suffix: str = "mp4", size: int = 1024, kind: str = "video") -> runner_io.Source:
    return runner_io.Source(Path(f"/work/in/sources/00.{suffix}"), content_type, kind, 0, None, size)


def request(sources: list | None = None, **inputs: str) -> runner_io.Request:
    values = {"source_asset_id": "asset-a", "target_resolution": "1080", "quality_preset": "quality", "preserve_audio": "true", "seed": "42"}
    values.update(inputs)
    return runner_io.Request(inputs={k: v for k, v in values.items() if v is not None}, sources=[source()] if sources is None else sources)


def probe(**overrides: object) -> dict:
    value = {"width": 720, "height": 1280, "fps": 12.0, "frames": 36, "duration_seconds": 3.0, "has_audio": True, "audio_codec": "aac"}
    value.update(overrides)
    return value


class PlanTest(unittest.TestCase):
    def test_a_catalog_request_plans_the_seedvr2_profile(self) -> None:
        plan = task.plan(request())
        self.assertEqual(plan["profile"], "seedvr2-3b")
        self.assertEqual((plan["target_resolution"], plan["seed"], plan["preserve_audio"]), (1080, 42, True))
        self.assertEqual(plan["source"], "/work/in/sources/00.mp4")

    def test_catalog_defaults_apply_when_inputs_are_absent(self) -> None:
        plan = task.plan(request(target_resolution=None, quality_preset=None, preserve_audio=None, seed=None))
        self.assertEqual((plan["target_resolution"], plan["seed"], plan["preserve_audio"]), (1080, 42, True))
        self.assertFalse(task.plan(request(preserve_audio="false"))["preserve_audio"])
        self.assertEqual(task.plan(request(seed="4294967295"))["seed"], 4294967295)

    def test_unsupported_parameters_are_refused(self) -> None:
        for name, value in (
            ("target_resolution", "0"), ("target_resolution", "720"), ("target_resolution", "1920"),
            ("quality_preset", "../../model"), ("seed", "-1"), ("seed", str(2**32)), ("seed", "1.5"),
            ("preserve_audio", "maybe"), ("source_asset_id", "a" * 65),
        ):
            with self.subTest(name=name, value=value), self.assertRaisesRegex(runner_io.RequestError, name):
                task.plan(request(**{name: value}))

    def test_inputs_the_catalog_does_not_declare_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt="x"))

    def test_exactly_one_video_source_is_required(self) -> None:
        for sources in ([], [source(), source()], [source("image/png", "png", kind="image")]):
            with self.subTest(count=len(sources)), self.assertRaisesRegex(runner_io.RequestError, "source"):
                task.plan(request(sources=sources))

    def test_only_mp4_and_webm_sources_up_to_512_mib_are_accepted(self) -> None:
        self.assertEqual(task.plan(request(sources=[source("video/webm", "webm")]))["source"], "/work/in/sources/00.webm")
        with self.assertRaisesRegex(runner_io.RequestError, "MP4 or WebM"):
            task.plan(request(sources=[source("video/quicktime", "mov")]))
        with self.assertRaisesRegex(runner_io.RequestError, "512 MiB"):
            task.plan(request(sources=[source(size=512 * 1024**2 + 1)]))


class GraphTest(unittest.TestCase):
    def graphs(self) -> list[dict]:
        plan = task.plan(request(seed="7"))
        return [task.graph(plan, "seedvr2-input.mp4", preset) for preset in task.PRESETS]

    def test_quality_graph_is_fp16_with_production_defaults(self) -> None:
        graph = self.graphs()[0]
        dit, vae, upscale = graph["3"]["inputs"], graph["4"]["inputs"], graph["5"]["inputs"]
        self.assertEqual(graph["1"]["inputs"]["file"], "seedvr2-input.mp4")
        self.assertEqual((dit["model"], dit["device"], dit["blocks_to_swap"], dit["offload_device"]), (FP16, "cuda:0", 0, "none"))
        self.assertEqual(vae["model"], VAE)
        self.assertFalse(vae["encode_tiled"] or vae["decode_tiled"])
        self.assertEqual((upscale["seed"], upscale["resolution"], upscale["max_resolution"]), (7, 1080, 1920))
        self.assertEqual((upscale["batch_size"], upscale["temporal_overlap"], upscale["color_correction"]), (5, 1, "lab"))
        self.assertEqual((upscale["input_noise_scale"], upscale["latent_noise_scale"]), (0.0, 0.0))
        self.assertFalse(upscale["uniform_batch_size"])

    def test_fallbacks_trade_memory_never_resolution(self) -> None:
        self.assertEqual([preset.name for preset in task.PRESETS], ["quality", "vae_tiled", "cpu_blockswap", "fp8_memory_saver"])
        graphs = self.graphs()
        self.assertTrue(graphs[1]["4"]["inputs"]["encode_tiled"] and graphs[1]["4"]["inputs"]["decode_tiled"])
        self.assertEqual((graphs[1]["4"]["inputs"]["encode_tile_size"], graphs[1]["4"]["inputs"]["decode_tile_overlap"]), (1024, 128))
        self.assertEqual(graphs[2]["3"]["inputs"]["offload_device"], "cpu")
        self.assertGreater(graphs[2]["3"]["inputs"]["blocks_to_swap"], 0)
        self.assertEqual(graphs[3]["3"]["inputs"]["model"], FP8)
        self.assertEqual([preset.quality_changed for preset in task.PRESETS], [False, False, False, True])
        self.assertEqual({g["5"]["inputs"]["resolution"] for g in graphs}, {1080})
        self.assertEqual({g["5"]["inputs"]["max_resolution"] for g in graphs}, {1920})

    def test_graph_uses_only_core_video_and_seedvr2_nodes(self) -> None:
        for graph in self.graphs():
            self.assertEqual({node["class_type"] for node in graph.values()}, task.REQUIRED_NODE_CLASSES)
            json.dumps(graph)

    def test_building_a_graph_leaves_the_template_untouched(self) -> None:
        self.graphs()
        template = json.loads(task.GRAPH_TEMPLATE.read_text(encoding="utf-8"))
        self.assertEqual(task.graph(task.plan(request(seed="42")), "seedvr2-input.mp4", task.PRESETS[0])["3"], template["3"])

    def test_every_model_a_graph_loads_is_in_the_profile(self) -> None:
        manifest = models.load_manifest(RUNNER / "models.json")
        profile = set(manifest.profiles[task.plan(request())["profile"]])
        for graph in self.graphs():
            for node in ("3", "4"):
                self.assertIn(f"SEEDVR2/{graph[node]['inputs']['model']}", profile)


class ModelFolderTest(unittest.TestCase):
    def setUp(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        self.root = temp.path
        (self.root / "SEEDVR2").mkdir()
        self.weights = {name: f"example {name} weights".encode() for name in (FP16, VAE, FP8)}
        self.manifest = self.root / "models.json"
        files = [
            {"path": f"SEEDVR2/{name}", "size_bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
             "source": "https://huggingface.co/example-org/example-model", "license": "Apache-2.0"}
            for name, data in self.weights.items()
        ]
        self.manifest.write_text(json.dumps({"files": files}), encoding="utf-8")

    def place(self, *names: str) -> None:
        for name in names:
            (self.root / "SEEDVR2" / name).write_bytes(self.weights[name])

    def test_the_shipped_manifest_pins_every_weight_by_revision_and_hash(self) -> None:
        manifest = models.load_manifest(RUNNER / "models.json")
        self.assertEqual(manifest.runner, "seedvr2-video")
        files = manifest.files
        self.assertEqual(files[f"SEEDVR2/{FP16}"].sha256, "2fd0e03a3dad24e07086750360727ca437de4ecd456f769856e960ae93e2b304")
        self.assertEqual(files[f"SEEDVR2/{VAE}"].sha256, "20678548f420d98d26f11442d3528f8b8c94e57ee046ef93dbb7633da8612ca1")
        self.assertEqual(files[f"SEEDVR2/{FP8}"].sha256, "3bf1e43ebedd570e7e7a0b1b60d6a02e105978f505c8128a241cde99a8240cff")
        self.assertEqual(sum(item.size_bytes for item in files.values()), 6783018808 + 501324814 + 3391544696)
        self.assertEqual([path for path, item in files.items() if item.optional], [f"SEEDVR2/{FP8}"])
        for item in files.values():
            self.assertIn("/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/", item.source)
            self.assertEqual(item.license, "Apache-2.0")

    def test_the_fp8_fallback_runs_only_when_its_optional_file_is_present(self) -> None:
        self.place(FP16, VAE)
        self.assertEqual([preset.name for preset in task.presets_available(self.root)], ["quality", "vae_tiled", "cpu_blockswap"])
        self.place(FP8)
        self.assertEqual(len(task.presets_available(self.root)), 4)

    def test_a_missing_or_altered_weight_is_refused_without_downloading(self) -> None:
        with self.assertRaisesRegex(RuntimeError, f"{FP16} is missing"):
            task.verify_models(self.root, [FP16, VAE], manifest_path=self.manifest)
        self.place(VAE)
        (self.root / "SEEDVR2" / FP16).write_bytes(b"x" * len(self.weights[FP16]))
        with self.assertRaisesRegex(RuntimeError, f"{FP16} sha256"):
            task.verify_models(self.root, [FP16, VAE], manifest_path=self.manifest)

    def test_verified_weights_get_a_node_validation_cache(self) -> None:
        self.place(FP16, VAE)
        entries = task.verify_models(self.root, [FP16, VAE], manifest_path=self.manifest)
        cache_dir = self.root / "node-cache"
        path = task.write_validation_cache(cache_dir, entries)
        cache = json.loads(path.read_text(encoding="utf-8"))
        weight = self.root / "SEEDVR2" / VAE
        self.assertEqual(path.name, ".validation_cache.json")
        self.assertEqual(cache[VAE], {"size": weight.stat().st_size, "mtime": os.path.getmtime(weight), "hash": hashlib.sha256(self.weights[VAE]).hexdigest()})
        self.assertEqual(sorted(cache), sorted([FP16, VAE]))

    def test_out_of_memory_is_recognised_in_errors_and_logs(self) -> None:
        self.assertTrue(task.is_cuda_oom("torch.OutOfMemoryError: CUDA out of memory. Tried to allocate 2.00 GiB"))
        self.assertTrue(task.is_cuda_oom("CUDA error: memory allocation failed"))
        self.assertFalse(task.is_cuda_oom("ComfyUI generation failed: invalid prompt"))


class MediaTest(unittest.TestCase):
    def test_ffprobe_output_is_summarised(self) -> None:
        document = {
            "streams": [
                {"codec_type": "video", "width": 720, "height": 1280, "avg_frame_rate": "24000/1001", "nb_read_frames": "72", "duration": "3.003"},
                {"codec_type": "audio", "codec_name": "aac"},
            ],
            "format": {"duration": "3.010"},
        }
        summary = media.parse_probe(document)
        self.assertEqual((summary["width"], summary["height"], summary["frames"], summary["has_audio"]), (720, 1280, 72, True))
        self.assertAlmostEqual(summary["fps"], 23.976, places=3)
        self.assertEqual(summary["duration_seconds"], 3.003)
        with self.assertRaisesRegex(RuntimeError, "video stream"):
            media.parse_probe({"streams": [{"codec_type": "audio"}]})

    def test_fields_ffprobe_reports_as_not_available_fall_back(self) -> None:
        webm = {"streams": [{"codec_type": "video", "width": 640, "height": 360, "avg_frame_rate": "0/0",
                             "r_frame_rate": "30/1", "nb_frames": "N/A", "nb_read_frames": "90", "duration": "N/A"}],
                "format": {"duration": "3.000000"}}
        summary = media.parse_probe(webm)
        self.assertEqual((summary["fps"], summary["frames"], summary["duration_seconds"]), (30.0, 90, 3.0))

    def test_an_unreadable_source_is_refused_with_the_stable_code(self) -> None:
        unreadable = lambda command, **_: subprocess.CompletedProcess(command, 1, stdout="", stderr="invalid data")  # noqa: E731
        with self.assertRaises(RuntimeError) as output_error:
            media.probe(Path("video.mp4"), run=unreadable)
        self.assertNotIsInstance(output_error.exception, runner_io.RequestError)
        with self.assertRaisesRegex(runner_io.RequestError, "could not be read") as caught:
            media.probe_source(Path("00.mp4"), run=unreadable)
        self.assertEqual(caught.exception.code, media.SOURCE_UNSUPPORTED)
        no_video = lambda command, **_: subprocess.CompletedProcess(command, 0, stdout='{"streams": []}')  # noqa: E731
        with self.assertRaisesRegex(runner_io.RequestError, "video stream"):
            media.probe_source(Path("00.mp4"), run=no_video)

    def test_the_source_envelope_is_enforced_with_a_stable_code(self) -> None:
        media.check_source(probe())
        media.check_source(probe(width=1920, height=1080))
        for overrides, message in (
            ({"width": 720, "height": 1920}, "aspect ratio"), ({"duration_seconds": 30.5}, "30 seconds"),
            ({"frames": 1801}, "1800 frames"), ({"fps": 61.0}, "frame rate"), ({"width": 4097, "height": 2400}, "4096"),
        ):
            with self.subTest(overrides=overrides), self.assertRaisesRegex(runner_io.RequestError, message) as caught:
                media.check_source(probe(**overrides))
            self.assertEqual(caught.exception.code, media.SOURCE_UNSUPPORTED)

    def test_the_output_must_keep_frames_rate_and_aspect_at_1080(self) -> None:
        source = probe()
        media.check_output(source, probe(width=1080, height=1920), target=1080)
        for overrides in ({"frames": 35}, {"fps": 24.0}, {"width": 1080, "height": 1080}, {"width": 720}):
            output = probe(width=1080, height=1920)
            output.update(overrides)
            with self.subTest(overrides=overrides), self.assertRaises(RuntimeError):
                media.check_output(source, output, target=1080)

    def test_remux_copies_source_audio_then_falls_back_to_aac(self) -> None:
        calls: list[list[str]] = []

        def fail_copy(command: list[str], **_: object) -> subprocess.CompletedProcess:
            calls.append(command)
            return subprocess.CompletedProcess(command, 1 if command[command.index("-c:a") + 1] == "copy" else 0)

        mode = media.remux(Path("r.mp4"), Path("s.webm"), Path("out.mp4"), keep_audio=True, run=fail_copy)
        self.assertEqual(mode, "aac_fallback")
        self.assertEqual([c[c.index("-c:a") + 1] for c in calls], ["copy", "aac"])
        self.assertTrue(all("1:a:0" in c and "+faststart" in c for c in calls))

    def test_remux_without_audio_keeps_only_the_upscaled_video(self) -> None:
        calls: list[list[str]] = []
        ok = lambda command, **_: calls.append(command) or subprocess.CompletedProcess(command, 0)  # noqa: E731
        self.assertEqual(media.remux(Path("r.mp4"), Path("s.mp4"), Path("out.mp4"), keep_audio=False, run=ok), "video_only")
        self.assertEqual(len(calls), 1)
        self.assertNotIn("1:a:0", calls[0])
        self.assertIn("+faststart", calls[0])

    def test_a_poster_is_optional_and_must_be_a_small_png(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        poster = temp.path / "poster.png"

        def writes(data: bytes):
            def run(command: list[str], **_: object) -> subprocess.CompletedProcess:
                Path(command[-1]).write_bytes(data)
                return subprocess.CompletedProcess(command, 0)
            return run

        self.assertTrue(media.extract_poster(Path("video.mp4"), poster, run=writes(b"\x89PNG\r\n\x1a\n" + b"0" * 16)))
        self.assertFalse(media.extract_poster(Path("video.mp4"), poster, run=writes(b"not a png")))
        self.assertFalse(poster.exists())
        failing = lambda command, **_: subprocess.CompletedProcess(command, 1)  # noqa: E731
        self.assertFalse(media.extract_poster(Path("video.mp4"), poster, run=failing))


class PackagingTest(unittest.TestCase):
    def test_the_workflow_serves_the_catalog_entry(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        for name in CATALOG_INPUTS + ("ii_request_id", "ii_payload_mode"):
            self.assertRegex(text, rf"\n      {name}:\n")
        for expected in (
            "RUNNER_NAME: seedvr2-video", "RUNNER_TASK: video-upscale", "II_OS_RUNNER_IMAGE_SEEDVR2_VIDEO",
            'max-sources: "1"', "source-kinds: video", "allowed-content-types: video/mp4,image/png",
            'max-bytes: "2147483648"', "error-code: video_upscale_failed", "cancelled-error-code: video_upscale_cancelled",
            f"runner-error-codes: {media.SOURCE_UNSUPPORTED}", "timeout-minutes: 120", "--gpu",
        ):
            self.assertIn(expected, text)

    def test_the_image_pins_the_node_and_its_compatibility_patch(self) -> None:
        dockerfile = (RUNNER / "Dockerfile").read_text(encoding="utf-8")
        patch = RUNNER / "seedvr2-transformers-5-flash-attn.patch"
        self.assertRegex(dockerfile, r"\nFROM nvidia/cuda:[^\s@]+@sha256:[0-9a-f]{64}\n")
        self.assertIn("SEEDVR2_NODE_REVISION=4490bd1f482e026674543386bb2a4d176da245b9", dockerfile)
        self.assertIn(f"SEEDVR2_PATCH_SHA256={hashlib.sha256(patch.read_bytes()).hexdigest()}", dockerfile)
        self.assertIn(f"ln -s {task.NODE_CACHE_DIR} /opt/ComfyUI/models/SEEDVR2", dockerfile)
        self.assertNotRegex(dockerfile, r"(curl|wget)[^\n]*\|\s*(ba)?sh")
        lock = (RUNNER / "requirements.lock.txt").read_text(encoding="utf-8")
        pinned = set(re.findall(r"^([A-Za-z0-9_.-]+)==[0-9]", lock, flags=re.MULTILINE))
        for package in ("diffusers", "peft", "omegaconf", "gguf", "rotary-embedding-torch", "matplotlib", "transformers"):
            self.assertIn(package, pinned)
        self.assertEqual(
            sorted(p.name for p in RUNNER.rglob("*") if re.search(r"requirements|\.lock", p.name)),
            ["requirements-build.lock.txt", "requirements.in", "requirements.lock.txt"],
        )

    def test_the_host_plans_a_staged_request(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        work = temp.path / "in"
        (work / "sources").mkdir(parents=True)
        (work / "sources" / "00.mp4").write_bytes(b"\x00\x00\x00\x18ftypmp42")
        inputs = {"source_asset_id": "asset-a", "target_resolution": "1080", "quality_preset": "quality", "preserve_audio": "true", "seed": "42"}
        (work / "inputs.json").write_text(json.dumps(inputs), encoding="utf-8")
        staged = [{"file": "sources/00.mp4", "ordinal": 0, "kind": "video", "contentType": "video/mp4", "sizeBytes": 12}]
        (work / "sources.json").write_text(json.dumps(staged), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, "-I", str(RUNNER / "entrypoint.py"), "plan", "--task", "video-upscale", "--input-dir", str(work)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), {"task": "video-upscale", "profile": "seedvr2-3b"})


if __name__ == "__main__":
    unittest.main()
