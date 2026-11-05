"""comfyui-image qwen-image-edit: request validation, mask regions and the
ComfyUI graphs for Qwen Image Edit 2511 (catalog ids image-edit-qwen-2511 and
image-create-reference-qwen-2511) and Qwen Image InstantX inpainting
(image-inpaint-qwen)."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

from tests.support import RUNNERS, TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
support = load("runners/comfyui-image/tasks/image_edit_support.py", "image_edit_support")
task = load("runners/comfyui-image/tasks/qwen_image_edit.py", "kit_comfyui_image_qwen_image_edit")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

RECT = {"mask_x": "0.1", "mask_y": "0.2", "mask_width": "0.3", "mask_height": "0.4"}
SOURCE_IDS = ("source_asset_id", "source_asset_id_2", "source_asset_id_3")


def image(ordinal: int = 0, *, kind: str = "image", suffix: str = "png", asset_id: str = "") -> runner_io.Source:
    return runner_io.Source(
        path=Path(f"/work/in/sources/{ordinal:02d}.{suffix}"), content_type=f"image/{suffix}",
        kind=kind, ordinal=ordinal, role=None, size_bytes=1024, asset_id=asset_id,
    )


def edit(count: int = 1, **inputs: str) -> runner_io.Request:
    ids = {name: f"asset-{index}" for index, name in enumerate(SOURCE_IDS[:count])}
    base = {"mode": "edit", "prompt": "give her a short bob", **ids}
    return runner_io.Request(inputs={**base, **inputs}, sources=[image(index) for index in range(count)])


def inpaint(*, sources: list | None = None, **inputs: str) -> runner_io.Request:
    base = {"mode": "inpaint", "source_asset_id": "asset-0", "prompt": "a blue scarf", "control_strength": "1", **RECT}
    return runner_io.Request(inputs={**base, **inputs}, sources=[image()] if sources is None else sources)


def nodes(graph: dict, class_type: str) -> list[dict]:
    return [node for node in graph.values() if node["class_type"] == class_type]


class EditPlanTest(unittest.TestCase):
    def test_edit_and_inpaint_use_their_own_profiles(self) -> None:
        self.assertEqual(task.plan(edit())["profile"], "qwen-image-edit-2511")
        self.assertEqual(task.plan(inpaint())["profile"], "qwen-image-inpaint")

    def test_edit_reads_one_to_three_ordered_images(self) -> None:
        self.assertEqual(task.plan(edit(3))["images"], ["ii-os-source-00.png", "ii-os-source-01.png", "ii-os-source-02.png"])
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(runner_io.Request(inputs=edit().inputs, sources=[]))
        four = runner_io.Request(inputs=edit(3).inputs, sources=[image(index) for index in range(4)])
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(four)

    def test_staged_images_must_match_the_named_source_ids(self) -> None:
        mismatched = runner_io.Request(inputs=edit(1).inputs, sources=[image(0), image(1)])
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(mismatched)
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id"):
            task.plan(edit(1, source_asset_id=""))

    def test_staged_asset_ids_must_follow_the_named_inputs_in_order(self) -> None:
        inputs = edit(2).inputs
        matching = runner_io.Request(inputs, [image(0, asset_id="asset-0"), image(1, asset_id="asset-1")])
        self.assertEqual(task.plan(matching)["images"], ["ii-os-source-00.png", "ii-os-source-01.png"])
        swapped = runner_io.Request(inputs, [image(0, asset_id="asset-1"), image(1, asset_id="asset-0")])
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id"):
            task.plan(swapped)
        foreign = runner_io.Request(inputs, [image(0, asset_id="asset-0"), image(1, asset_id="asset-9")])
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id_2"):
            task.plan(foreign)

    def test_only_image_sources_are_read(self) -> None:
        video = runner_io.Request(inputs=edit().inputs, sources=[image(kind="video", suffix="mp4")])
        with self.assertRaisesRegex(runner_io.RequestError, "image"):
            task.plan(video)

    def test_edit_refuses_mask_inputs(self) -> None:
        for name, value in {**RECT, "mask_regions": "[[0,0,1,1]]"}.items():
            with self.subTest(field=name), self.assertRaisesRegex(runner_io.RequestError, "edit mode"):
                task.plan(edit(**{name: value}))

    def test_edit_tolerates_but_ignores_a_control_strength(self) -> None:
        self.assertEqual(task.plan(edit(control_strength="0.65"))["profile"], "qwen-image-edit-2511")

    def test_prompt_mode_seed_and_undeclared_inputs(self) -> None:
        self.assertEqual(len(task.plan(edit(prompt="x" * 30000))["prompt"]), 30000)
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(edit(prompt="x" * 30001))
        with self.assertRaisesRegex(runner_io.RequestError, "mode"):
            task.plan(edit(mode="restyle"))
        self.assertEqual(task.plan(edit(seed="9"))["seed"], 9)
        with self.assertRaisesRegex(runner_io.RequestError, "aspect_ratio"):
            task.plan(edit(aspect_ratio="1:1"))


class InpaintPlanTest(unittest.TestCase):
    def test_inpaint_reads_exactly_one_image(self) -> None:
        two = inpaint(sources=[image(0), image(1)], source_asset_id_2="asset-1")
        with self.assertRaisesRegex(runner_io.RequestError, "one source image"):
            task.plan(two)

    def test_the_rectangle_alone_is_one_region(self) -> None:
        self.assertEqual(task.plan(inpaint())["mask_regions"], [[0.1, 0.2, 0.3, 0.4]])

    def test_regions_take_precedence_over_the_rectangle(self) -> None:
        planned = task.plan(inpaint(mask_regions="[[0.1,0.1,0.2,0.2],[0.7,0.65,0.15,0.2]]"))
        self.assertEqual(planned["mask_regions"], [[0.1, 0.1, 0.2, 0.2], [0.7, 0.65, 0.15, 0.2]])
        only_regions = {key: value for key, value in inpaint(mask_regions="[[0,0,1,1]]").inputs.items() if key not in RECT}
        self.assertEqual(task.plan(runner_io.Request(only_regions, [image()]))["mask_regions"], [[0, 0, 1, 1]])

    def test_a_mask_is_required(self) -> None:
        bare = {key: value for key, value in inpaint().inputs.items() if key not in RECT}
        with self.assertRaisesRegex(runner_io.RequestError, "mask"):
            task.plan(runner_io.Request(bare, [image()]))

    def test_a_partial_rectangle_is_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "mask"):
            task.plan(inpaint(mask_height=""))
        with self.assertRaisesRegex(runner_io.RequestError, "mask"):
            task.plan(inpaint(mask_height="", mask_regions="[[0,0,1,1]]"))

    def test_malformed_regions_are_refused(self) -> None:
        cases = {
            "not json": "[[0.1,0.1,0.2",
            "not a list": '{"x": 0.1}',
            "empty": "[]",
            "33 regions": json.dumps([[0, 0, 0.01, 0.01]] * 33),
            "region not a list": "[0.1, 0.1, 0.2, 0.2]",
            "three values": "[[0.1,0.1,0.2]]",
            "string value": '[["0.1",0.2,0.3,0.4]]',
            "boolean value": "[[true,0.2,0.3,0.4]]",
            "nan": "[[NaN,0.2,0.3,0.4]]",
            "infinite": "[[0.1,0.2,Infinity,0.4]]",
            "negative": "[[-0.1,0.2,0.3,0.4]]",
            "past the edge": "[[0.8,0.2,0.3,0.4]]",
            "zero width": "[[0.1,0.2,0,0.4]]",
        }
        for label, value in cases.items():
            with self.subTest(case=label), self.assertRaisesRegex(runner_io.RequestError, "mask_regions"):
                task.plan(inpaint(mask_regions=value))

    def test_thirty_two_regions_and_a_rounding_overshoot_are_accepted(self) -> None:
        self.assertEqual(len(task.plan(inpaint(mask_regions=json.dumps([[0, 0, 0.01, 0.01]] * 32)))["mask_regions"]), 32)
        self.assertEqual(task.plan(inpaint(mask_regions="[[0.5,0,0.50009,1]]"))["mask_regions"], [[0.5, 0, 0.50009, 1]])

    def test_control_strength_defaults_to_one_and_is_bounded(self) -> None:
        self.assertEqual(task.plan(inpaint(control_strength=""))["control_strength"], 1.0)
        self.assertEqual(task.plan(inpaint(control_strength="0.5"))["control_strength"], 0.5)
        for bad in ("-0.5", "10.5", "full"):
            with self.subTest(value=bad), self.assertRaisesRegex(runner_io.RequestError, "control_strength"):
                task.plan(inpaint(control_strength=bad))

    def test_inpaint_prompts_are_shorter(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(inpaint(prompt="x" * 4001))


class MaskGeometryTest(unittest.TestCase):
    def test_disconnected_regions_become_separate_pixel_boxes(self) -> None:
        boxes = support.mask_boxes([[0.1, 0.1, 0.2, 0.2], [0.7, 0.65, 0.15, 0.2]], 100, 100)
        self.assertEqual(boxes, [(10, 10, 30, 30), (70, 65, 85, 85)])

    def test_a_sliver_still_covers_at_least_one_pixel(self) -> None:
        self.assertEqual(support.mask_boxes([[0.5, 0.5, 0.0001, 0.0001]], 100, 100), [(50, 50, 51, 51)])


class GraphTest(unittest.TestCase):
    def test_edit_graph_feeds_every_image_to_both_text_encoders(self) -> None:
        graph = task.graph(task.plan(edit(3, prompt="swap the hats", seed="5")))
        encoders = nodes(graph, "TextEncodeQwenImageEditPlus")
        self.assertEqual(sorted(node["inputs"]["prompt"] for node in encoders), ["", "swap the hats"])
        for encoder in encoders:
            loaded = [graph[encoder["inputs"][f"image{index}"][0]] for index in (2, 3)]
            self.assertEqual([node["inputs"]["image"] for node in loaded], ["ii-os-source-01.png", "ii-os-source-02.png"])
            self.assertEqual(graph[encoder["inputs"]["image1"][0]]["class_type"], "FluxKontextImageScale")

    def test_edit_graph_uses_the_lightning_lora_at_four_steps(self) -> None:
        graph = task.graph(task.plan(edit(seed="5")))
        self.assertEqual(nodes(graph, "LoraLoaderModelOnly")[0]["inputs"]["lora_name"], "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors")
        sampler = nodes(graph, "KSampler")[0]["inputs"]
        self.assertEqual((sampler["steps"], sampler["cfg"], sampler["seed"]), (4, 1.0, 5))
        self.assertEqual(len(nodes(graph, "CFGNorm")), 1)
        self.assertNotIn("image2", nodes(graph, "TextEncodeQwenImageEditPlus")[0]["inputs"])

    def test_inpaint_graph_masks_the_latent_and_composites_over_the_source(self) -> None:
        graph = task.graph(task.plan(inpaint(control_strength="0.7")))
        control = nodes(graph, "ControlNetInpaintingAliMamaApply")[0]["inputs"]
        self.assertEqual(control["strength"], 0.7)
        self.assertEqual(nodes(graph, "ControlNetLoader")[0]["inputs"]["control_net_name"], "Qwen-Image-InstantX-ControlNet-Inpainting.safetensors")
        sampler = nodes(graph, "KSampler")[0]["inputs"]
        self.assertEqual(graph[sampler["latent_image"][0]]["class_type"], "SetLatentNoiseMask")
        self.assertEqual(sampler["positive"][1], 0)
        self.assertEqual(sampler["negative"][1], 1)
        self.assertEqual(sorted(node["inputs"]["image"] for node in nodes(graph, "LoadImage")), ["ii-os-mask.png", "ii-os-source-00.png"])
        composite = nodes(graph, "ImageCompositeMasked")[0]["inputs"]
        self.assertEqual(graph[composite["source"][0]]["class_type"], "VAEDecode")
        self.assertEqual(graph[nodes(graph, "SaveImage")[0]["inputs"]["images"][0]]["class_type"], "ImageCompositeMasked")

    def test_every_model_file_a_graph_loads_is_in_its_profile(self) -> None:
        manifest = models.load_manifest(RUNNERS / "comfyui-image" / "models.json")
        loaders = {
            "UNETLoader": ("unet_name", "diffusion_models"),
            "CLIPLoader": ("clip_name", "text_encoders"),
            "VAELoader": ("vae_name", "vae"),
            "LoraLoaderModelOnly": ("lora_name", "loras"),
            "ControlNetLoader": ("control_net_name", "controlnet"),
        }
        for planned, expected in ((task.plan(edit(2)), 4), (task.plan(inpaint()), 5)):
            profile = manifest.profiles[planned["profile"]]
            loaded = [
                f"{loaders[node['class_type']][1]}/{node['inputs'][loaders[node['class_type']][0]]}"
                for node in task.graph(planned).values() if node["class_type"] in loaders
            ]
            with self.subTest(profile=planned["profile"]):
                self.assertEqual(sorted(loaded), sorted(profile))
                self.assertEqual(len(loaded), expected)

    def test_the_text_encoder_is_the_apache_licensed_copy(self) -> None:
        manifest = models.load_manifest(RUNNERS / "comfyui-image" / "models.json")
        encoder = manifest.files["text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"]
        self.assertIn("Comfy-Org/Qwen-Image_ComfyUI/", encoder.source)
        self.assertEqual(encoder.license, "Apache-2.0")

    def test_graphs_are_plain_json(self) -> None:
        json.dumps(task.graph(task.plan(edit(3))))
        json.dumps(task.graph(task.plan(inpaint(mask_regions="[[0,0,0.5,0.5],[0.5,0.5,0.5,0.5]]"))))


class HostPlanTest(unittest.TestCase):
    def test_the_host_plans_a_staged_request_without_echoing_the_prompt(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        work = temp.path / "in"
        (work / "sources").mkdir(parents=True)
        staged = []
        for ordinal in range(2):
            (work / "sources" / f"{ordinal:02d}.jpg").write_bytes(b"\xff\xd8\xff")
            staged.append({
                "assetId": f"asset-{'ab'[ordinal]}", "file": f"sources/{ordinal:02d}.jpg", "ordinal": ordinal,
                "kind": "image", "contentType": "image/jpeg", "sizeBytes": 3,
            })
        inputs = {"mode": "edit", "source_asset_id": "asset-a", "source_asset_id_2": "asset-b", "prompt": "secret wording"}
        (work / "inputs.json").write_text(json.dumps(inputs), encoding="utf-8")
        (work / "sources.json").write_text(json.dumps(staged), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, "-I", str(RUNNERS / "comfyui-image" / "entrypoint.py"), "plan", "--task", "qwen-image-edit", "--input-dir", str(work)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), {"task": "qwen-image-edit", "profile": "qwen-image-edit-2511"})
        self.assertNotIn("secret wording", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
