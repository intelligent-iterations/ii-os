"""comfyui-image text-to-image: request validation and the ComfyUI graphs for
Z-Image Turbo, FLUX.2 Klein 4B and Qwen-Image 2512."""

from __future__ import annotations

import json
import unittest

from tests.support import RUNNERS, load

runner_io = load("runners/common/runner_io.py", "runner_io")
task = load("runners/comfyui-image/tasks/text_to_image.py", "kit_comfyui_image_text_to_image")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")


def request(**inputs: str) -> runner_io.Request:
    return runner_io.Request(inputs={"prompt": "a lighthouse at dusk", "aspect_ratio": "1:1", **inputs}, sources=[])


def nodes(graph: dict, class_type: str) -> list[dict]:
    return [node for node in graph.values() if node["class_type"] == class_type]


class PlanTest(unittest.TestCase):
    def test_each_model_maps_to_its_profile(self) -> None:
        for model, profile in (("z-image-turbo", "z-image-turbo"), ("flux2-klein", "flux2-klein"), ("qwen-image-2512", "qwen-image-2512")):
            with self.subTest(model=model):
                self.assertEqual(task.plan(request(model=model))["profile"], profile)

    def test_an_absent_model_means_z_image_turbo(self) -> None:
        self.assertEqual(task.plan(request())["profile"], "z-image-turbo")

    def test_an_unknown_model_is_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "model"):
            task.plan(request(model="sdxl"))

    def test_aspect_ratios_map_to_model_native_sizes(self) -> None:
        self.assertEqual(task.plan(request(aspect_ratio="16:9"))["size"], [1344, 768])
        self.assertEqual(task.plan(request(model="qwen-image-2512", aspect_ratio="1:1"))["size"], [1328, 1328])
        self.assertEqual(task.plan(request(model="flux2-klein", aspect_ratio="3:2"))["size"], [1152, 768])
        with self.assertRaisesRegex(runner_io.RequestError, "aspect_ratio"):
            task.plan(request(aspect_ratio="21:9"))

    def test_prompt_and_seed_are_validated(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt=" "))
        with self.assertRaisesRegex(runner_io.RequestError, "seed"):
            task.plan(request(seed="-1"))
        self.assertEqual(task.plan(request(seed="7"))["seed"], 7)
        self.assertGreater(task.plan(request())["seed"], 0)

    def test_inputs_the_catalog_does_not_declare_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id"):
            task.plan(request(source_asset_id="x"))

    def test_this_task_reads_no_source_assets(self) -> None:
        with_source = runner_io.Request(inputs=request().inputs, sources=[object()])  # type: ignore[list-item]
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(with_source)


class GraphTest(unittest.TestCase):
    def test_z_image_graph_carries_the_request(self) -> None:
        plan = task.plan(request(prompt="a red fox in snow", aspect_ratio="9:16", seed="11"))
        graph = task.graph(plan)
        self.assertEqual(nodes(graph, "CLIPTextEncode")[0]["inputs"]["text"], "a red fox in snow")
        latent = nodes(graph, "EmptySD3LatentImage")[0]["inputs"]
        self.assertEqual((latent["width"], latent["height"]), (768, 1344))
        sampler = nodes(graph, "KSampler")[0]["inputs"]
        self.assertEqual((sampler["seed"], sampler["steps"], sampler["cfg"]), (11, 8, 1))
        self.assertEqual(nodes(graph, "UNETLoader")[0]["inputs"]["unet_name"], "z_image_turbo_bf16.safetensors")

    def test_flux2_graph_uses_the_distilled_fp8_model(self) -> None:
        graph = task.graph(task.plan(request(model="flux2-klein")))
        self.assertEqual(nodes(graph, "UNETLoader")[0]["inputs"]["unet_name"], "flux-2-klein-4b-fp8.safetensors")
        self.assertEqual(nodes(graph, "Flux2Scheduler")[0]["inputs"]["steps"], 4)
        self.assertEqual(nodes(graph, "CLIPLoader")[0]["inputs"]["type"], "flux2")

    def test_qwen_graph_needs_no_lightning_lora(self) -> None:
        graph = task.graph(task.plan(request(model="qwen-image-2512")))
        self.assertEqual(nodes(graph, "LoraLoaderModelOnly"), [])
        self.assertEqual(nodes(graph, "KSampler")[0]["inputs"]["steps"], 50)

    def test_every_model_file_a_graph_loads_is_in_its_profile(self) -> None:
        manifest = models.load_manifest(RUNNERS / "comfyui-image" / "models.json")
        loaders = {
            "UNETLoader": ("unet_name", "diffusion_models"),
            "CLIPLoader": ("clip_name", "text_encoders"),
            "VAELoader": ("vae_name", "vae"),
        }
        for model in ("z-image-turbo", "flux2-klein", "qwen-image-2512"):
            plan = task.plan(request(model=model))
            profile = set(manifest.profiles[plan["profile"]])
            for node in task.graph(plan).values():
                if node["class_type"] in loaders:
                    field, folder = loaders[node["class_type"]]
                    with self.subTest(model=model, node=node["class_type"]):
                        self.assertIn(f"{folder}/{node['inputs'][field]}", profile)

    def test_graphs_are_plain_json(self) -> None:
        for model in ("z-image-turbo", "flux2-klein", "qwen-image-2512"):
            json.dumps(task.graph(task.plan(request(model=model))))


if __name__ == "__main__":
    unittest.main()
