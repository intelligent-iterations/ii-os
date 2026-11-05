"""comfyui-image flux2-klein-edit: request validation and the ComfyUI graph for
the FLUX.2 Klein 4B base image-edit template (catalog ids
image-edit-flux2-klein and image-create-reference-flux2-klein)."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

from tests.support import RUNNERS, TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
task = load("runners/comfyui-image/tasks/flux2_klein_edit.py", "kit_comfyui_image_flux2_klein_edit")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")


def image(ordinal: int = 0, *, kind: str = "image", suffix: str = "png") -> runner_io.Source:
    return runner_io.Source(
        path=Path(f"/work/in/sources/{ordinal:02d}.{suffix}"), content_type=f"image/{suffix}",
        kind=kind, ordinal=ordinal, role=None, size_bytes=1024,
    )


def request(count: int = 1, **inputs: str) -> runner_io.Request:
    ids = {name: f"asset-{index}" for index, name in enumerate(("source_asset_id", "source_asset_id_2")[:count])}
    base = {"mode": "edit", "prompt": "keep the pose, change the haircut to a short bob", **ids}
    return runner_io.Request(inputs={**base, **inputs}, sources=[image(index) for index in range(count)])


def nodes(graph: dict, class_type: str) -> list[dict]:
    return [node for node in graph.values() if node["class_type"] == class_type]


class PlanTest(unittest.TestCase):
    def test_one_or_two_images_use_the_base_edit_profile(self) -> None:
        self.assertEqual(task.plan(request(1))["profile"], "flux2-klein-base-edit")
        self.assertEqual(task.plan(request(2))["images"], ["ii-os-source-00.png", "ii-os-source-01.png"])

    def test_more_than_two_images_or_none_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id_3"):
            task.plan(request(2, source_asset_id_3="asset-2"))
        three = runner_io.Request(inputs=request(2).inputs, sources=[image(0), image(1), image(2)])
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(three)
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(runner_io.Request(inputs=request().inputs, sources=[]))

    def test_staged_images_must_match_the_named_source_ids(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(runner_io.Request(inputs=request(1).inputs, sources=[image(0), image(1)]))
        with self.assertRaisesRegex(runner_io.RequestError, "image"):
            task.plan(runner_io.Request(inputs=request().inputs, sources=[image(kind="audio", suffix="wav")]))

    def test_a_storyboard_control_strength_is_accepted_and_ignored(self) -> None:
        # The dashboard's storyboard sends control_strength to every image-edit
        # template; this model has no control input, so the value is not used.
        plan = task.plan(request(control_strength="0.65"))
        self.assertEqual(plan["profile"], "flux2-klein-base-edit")
        self.assertNotIn("0.65", json.dumps(task.graph(plan)))
        with self.assertRaisesRegex(runner_io.RequestError, "control_strength"):
            task.plan(request(control_strength="not-a-number"))

    def test_only_edit_mode_exists(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "mode"):
            task.plan(request(mode="inpaint"))
        with self.assertRaisesRegex(runner_io.RequestError, "mode"):
            task.plan(request(mode=""))

    def test_mask_inputs_are_not_declared(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "mask_x"):
            task.plan(request(mask_x="0.1"))

    def test_prompt_and_seed(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt=""))
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt="x" * 30001))
        self.assertEqual(task.plan(request(seed="1234"))["seed"], 1234)
        self.assertGreater(task.plan(request())["seed"], 0)
        with self.assertRaisesRegex(runner_io.RequestError, "seed"):
            task.plan(request(seed="-3"))


class GraphTest(unittest.TestCase):
    def test_graph_follows_the_klein_base_edit_template(self) -> None:
        graph = task.graph(task.plan(request(prompt="a short bob", seed="1234")))
        self.assertEqual(nodes(graph, "UNETLoader")[0]["inputs"]["unet_name"], "flux-2-klein-base-4b-fp8.safetensors")
        self.assertEqual(nodes(graph, "CLIPLoader")[0]["inputs"]["type"], "flux2")
        self.assertEqual(nodes(graph, "VAELoader")[0]["inputs"]["vae_name"], "full_encoder_small_decoder.safetensors")
        self.assertEqual(sorted(node["inputs"]["text"] for node in nodes(graph, "CLIPTextEncode")), ["", "a short bob"])
        self.assertEqual(nodes(graph, "RandomNoise")[0]["inputs"]["noise_seed"], 1234)
        self.assertEqual(nodes(graph, "Flux2Scheduler")[0]["inputs"]["steps"], 20)
        self.assertEqual(nodes(graph, "CFGGuider")[0]["inputs"]["cfg"], 5.0)
        self.assertEqual(len(nodes(graph, "ReferenceLatent")), 2)

    def test_the_latent_takes_the_scaled_source_size(self) -> None:
        graph = task.graph(task.plan(request()))
        scale = nodes(graph, "ImageScaleToTotalPixels")[0]["inputs"]
        self.assertEqual((scale["megapixels"], scale["resolution_steps"]), (1.0, 1))
        for class_type in ("Flux2Scheduler", "EmptyFlux2LatentImage"):
            size = nodes(graph, class_type)[0]["inputs"]
            self.assertEqual(graph[size["width"][0]]["class_type"], "GetImageSize")
            self.assertEqual((size["width"][1], size["height"][1]), (0, 1))

    def test_a_second_image_chains_into_both_conditionings(self) -> None:
        graph = task.graph(task.plan(request(2)))
        self.assertEqual([node["inputs"]["image"] for node in nodes(graph, "LoadImage")], ["ii-os-source-00.png", "ii-os-source-01.png"])
        self.assertEqual(len(nodes(graph, "ReferenceLatent")), 4)
        guider = nodes(graph, "CFGGuider")[0]["inputs"]
        for side in ("positive", "negative"):
            outer = graph[guider[side][0]]
            self.assertEqual(outer["class_type"], "ReferenceLatent")
            self.assertEqual(graph[outer["inputs"]["conditioning"][0]]["class_type"], "ReferenceLatent")

    def test_every_model_file_the_graph_loads_is_in_its_profile(self) -> None:
        manifest = models.load_manifest(RUNNERS / "comfyui-image" / "models.json")
        loaders = {"UNETLoader": ("unet_name", "diffusion_models"), "CLIPLoader": ("clip_name", "text_encoders"), "VAELoader": ("vae_name", "vae")}
        planned = task.plan(request(2))
        loaded = sorted(
            f"{loaders[node['class_type']][1]}/{node['inputs'][loaders[node['class_type']][0]]}"
            for node in task.graph(planned).values() if node["class_type"] in loaders
        )
        self.assertEqual(loaded, sorted(manifest.profiles[planned["profile"]]))

    def test_graphs_are_plain_json(self) -> None:
        json.dumps(task.graph(task.plan(request(2))))


class HostPlanTest(unittest.TestCase):
    def test_the_host_plans_a_staged_request_without_echoing_the_prompt(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        work = temp.path / "in"
        (work / "sources").mkdir(parents=True)
        (work / "sources" / "00.webp").write_bytes(b"RIFF\x00\x00\x00\x00WEBP")
        (work / "inputs.json").write_text(json.dumps({"mode": "edit", "source_asset_id": "asset-a", "prompt": "secret wording"}), encoding="utf-8")
        staged = [{"file": "sources/00.webp", "ordinal": 0, "kind": "image", "contentType": "image/webp", "sizeBytes": 12}]
        (work / "sources.json").write_text(json.dumps(staged), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, "-I", str(RUNNERS / "comfyui-image" / "entrypoint.py"), "plan", "--task", "flux2-klein-edit", "--input-dir", str(work)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), {"task": "flux2-klein-edit", "profile": "flux2-klein-base-edit"})
        self.assertNotIn("secret wording", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
