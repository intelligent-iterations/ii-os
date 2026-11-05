"""comfyui-image z-image-edit: request validation, the mask rules and the
ComfyUI graphs for Z-Image Turbo with the Fun ControlNet Union 2.1 patch
(catalog ids image-edit and image-inpaint)."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

from tests.support import RUNNERS, TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
support = load("runners/comfyui-image/tasks/image_edit_support.py", "image_edit_support")
task = load("runners/comfyui-image/tasks/z_image_edit.py", "kit_comfyui_image_z_image_edit")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

MASK = {"mask_x": "0.25", "mask_y": "0.1", "mask_width": "0.5", "mask_height": "0.4"}


def image(ordinal: int = 0, *, kind: str = "image", suffix: str = "png", asset_id: str = "") -> runner_io.Source:
    return runner_io.Source(
        path=Path(f"/work/in/sources/{ordinal:02d}.{suffix}"), content_type=f"image/{suffix}",
        kind=kind, ordinal=ordinal, role=None, size_bytes=1024, asset_id=asset_id,
    )


def request(*, sources: list | None = None, **inputs: str) -> runner_io.Request:
    base = {"mode": "edit", "source_asset_id": "asset-a", "prompt": "make the jacket red", "control_strength": "1"}
    return runner_io.Request(inputs={**base, **inputs}, sources=[image()] if sources is None else sources)


def inpaint(**inputs: str) -> runner_io.Request:
    return request(**{"mode": "inpaint", **MASK, **inputs})


def nodes(graph: dict, class_type: str) -> list[dict]:
    return [node for node in graph.values() if node["class_type"] == class_type]


class PlanTest(unittest.TestCase):
    def test_both_modes_use_the_controlnet_profile(self) -> None:
        self.assertEqual(task.plan(request())["profile"], "z-image-turbo-controlnet")
        self.assertEqual(task.plan(inpaint())["profile"], "z-image-turbo-controlnet")

    def test_mode_is_required_and_closed(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "mode"):
            task.plan(request(mode=""))
        with self.assertRaisesRegex(runner_io.RequestError, "mode"):
            task.plan(request(mode="outpaint"))

    def test_the_source_image_is_staged_under_a_plain_name(self) -> None:
        self.assertEqual(task.plan(request())["images"], ["ii-os-source-00.png"])
        self.assertEqual(task.plan(request(sources=[image(suffix="jpg")]))["images"], ["ii-os-source-00.jpg"])

    def test_exactly_one_image_source_is_read(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(request(sources=[]))
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(request(sources=[image(0), image(1)]))
        with self.assertRaisesRegex(runner_io.RequestError, "image"):
            task.plan(request(sources=[image(kind="video", suffix="mp4")]))

    def test_a_staged_image_must_be_the_one_the_request_names(self) -> None:
        self.assertEqual(task.plan(request(sources=[image(asset_id="asset-a")]))["images"], ["ii-os-source-00.png"])
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id"):
            task.plan(request(sources=[image(asset_id="asset-b")]))

    def test_the_source_asset_id_is_required(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id"):
            task.plan(request(source_asset_id=""))

    def test_inputs_the_catalog_does_not_declare_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "source_asset_id_2"):
            task.plan(request(source_asset_id_2="asset-b"))
        with self.assertRaisesRegex(runner_io.RequestError, "mask_regions"):
            task.plan(inpaint(mask_regions="[[0,0,1,1]]"))

    def test_prompt_limits_follow_the_mode(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt="  "))
        self.assertEqual(len(task.plan(request(prompt="x" * 30000))["prompt"]), 30000)
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(request(prompt="x" * 30001))
        with self.assertRaisesRegex(runner_io.RequestError, "prompt"):
            task.plan(inpaint(prompt="x" * 4001))

    def test_control_strength_is_required_and_bounded(self) -> None:
        self.assertEqual(task.plan(request(control_strength="0.65"))["control_strength"], 0.65)
        self.assertEqual(task.plan(request(control_strength="-10"))["control_strength"], -10)
        for bad in ("", "10.5", "-11", "strong", "nan"):
            with self.subTest(value=bad), self.assertRaisesRegex(runner_io.RequestError, "control_strength"):
                task.plan(request(control_strength=bad))

    def test_seed_is_validated_or_drawn(self) -> None:
        self.assertEqual(task.plan(request(seed="42"))["seed"], 42)
        self.assertGreater(task.plan(request())["seed"], 0)
        with self.assertRaisesRegex(runner_io.RequestError, "seed"):
            task.plan(request(seed="1.5"))


class MaskTest(unittest.TestCase):
    def test_edit_mode_refuses_any_mask_field(self) -> None:
        for name in MASK:
            with self.subTest(field=name), self.assertRaisesRegex(runner_io.RequestError, "edit mode"):
                task.plan(request(**{name: MASK[name]}))

    def test_inpaint_needs_all_four_mask_fields(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "mask"):
            task.plan(request(mode="inpaint"))
        for name in MASK:
            with self.subTest(missing=name), self.assertRaisesRegex(runner_io.RequestError, "mask"):
                task.plan(inpaint(**{name: ""}))

    def test_the_rectangle_is_kept_normalised(self) -> None:
        self.assertEqual(task.plan(inpaint())["mask"], [0.25, 0.1, 0.5, 0.4])
        self.assertEqual(task.plan(inpaint(mask_x="0", mask_y="0", mask_width="1", mask_height="1"))["mask"], [0, 0, 1, 1])

    def test_a_rounding_overshoot_of_a_ten_thousandth_is_accepted(self) -> None:
        self.assertEqual(task.plan(inpaint(mask_x="0.5", mask_width="0.50009"))["mask"][2], 0.50009)

    def test_rectangles_outside_the_image_or_empty_are_refused(self) -> None:
        cases = {
            "past the right edge": {"mask_x": "0.6", "mask_width": "0.5"},
            "past the bottom edge": {"mask_y": "0.7", "mask_height": "0.4"},
            "zero width": {"mask_width": "0"},
            "zero height": {"mask_height": "0"},
            "negative x": {"mask_x": "-0.1"},
            "x beyond 1": {"mask_x": "1.2"},
            "not a number": {"mask_y": "top"},
            "infinite": {"mask_width": "inf"},
        }
        for label, override in cases.items():
            with self.subTest(case=label), self.assertRaisesRegex(runner_io.RequestError, "mask"):
                task.plan(inpaint(**override))

    def test_unchanged_and_neutral_grey_filler_pixels_fall_back_to_the_source(self) -> None:
        keep = support.keep_generated_pixel
        self.assertFalse(keep((116, 82, 64), (119, 108, 97)), "grey filler")
        self.assertFalse(keep((10, 20, 30), (12, 21, 33)), "unchanged")
        self.assertTrue(keep((116, 82, 64), (20, 80, 220)), "a real change")
        self.assertTrue(keep((10, 20, 30), (200, 100, 50)), "a real change")
        self.assertTrue(keep((10, 10, 10), (240, 240, 240)), "white is not filler")


class GraphTest(unittest.TestCase):
    def test_edit_graph_conditions_on_canny_edges_of_the_source(self) -> None:
        graph = task.graph(task.plan(request(prompt="a red jacket", control_strength="0.8", seed="7")))
        self.assertEqual(nodes(graph, "LoadImage")[0]["inputs"]["image"], "ii-os-source-00.png")
        self.assertEqual(nodes(graph, "ImageScaleToMaxDimension")[0]["inputs"]["largest_size"], 1024)
        canny = nodes(graph, "Canny")[0]["inputs"]
        self.assertEqual((canny["low_threshold"], canny["high_threshold"]), (0.1, 0.32))
        control = nodes(graph, "QwenImageDiffsynthControlnet")[0]["inputs"]
        self.assertEqual(control["strength"], 0.8)
        self.assertNotIn("mask", control)
        self.assertEqual(nodes(graph, "CLIPTextEncode")[0]["inputs"]["text"], "a red jacket")
        sampler = nodes(graph, "KSampler")[0]["inputs"]
        self.assertEqual((sampler["seed"], sampler["steps"], sampler["cfg"], sampler["sampler_name"]), (7, 9, 1.0, "res_multistep"))
        self.assertEqual(graph[sampler["latent_image"][0]]["class_type"], "EmptySD3LatentImage")
        self.assertEqual(nodes(graph, "VAEEncodeForInpaint"), [])
        self.assertEqual(graph[nodes(graph, "SaveImage")[0]["inputs"]["images"][0]]["class_type"], "VAEDecode")

    def test_inpaint_graph_encodes_the_masked_source_and_composites_over_it(self) -> None:
        graph = task.graph(task.plan(inpaint()))
        self.assertEqual(sorted(node["inputs"]["image"] for node in nodes(graph, "LoadImage")), ["ii-os-mask.png", "ii-os-source-00.png"])
        mask_ref = nodes(graph, "VAEEncodeForInpaint")[0]["inputs"]["mask"]
        self.assertEqual(graph[mask_ref[0]]["class_type"], "ImageToMask")
        self.assertEqual(nodes(graph, "VAEEncodeForInpaint")[0]["inputs"]["grow_mask_by"], 6)
        self.assertEqual(nodes(graph, "QwenImageDiffsynthControlnet")[0]["inputs"]["mask"], mask_ref)
        sampler = nodes(graph, "KSampler")[0]["inputs"]
        self.assertEqual(graph[sampler["latent_image"][0]]["class_type"], "VAEEncodeForInpaint")
        self.assertEqual(nodes(graph, "EmptySD3LatentImage"), [])
        composite = nodes(graph, "ImageCompositeMasked")[0]["inputs"]
        self.assertEqual(graph[composite["destination"][0]]["class_type"], "ImageScaleToMaxDimension")
        self.assertEqual(graph[composite["source"][0]]["class_type"], "VAEDecode")
        self.assertEqual(composite["mask"], mask_ref)
        self.assertEqual(graph[nodes(graph, "SaveImage")[0]["inputs"]["images"][0]]["class_type"], "ImageCompositeMasked")

    def test_every_model_file_a_graph_loads_is_in_its_profile(self) -> None:
        manifest = models.load_manifest(RUNNERS / "comfyui-image" / "models.json")
        loaders = {
            "UNETLoader": ("unet_name", "diffusion_models"),
            "CLIPLoader": ("clip_name", "text_encoders"),
            "VAELoader": ("vae_name", "vae"),
            "ModelPatchLoader": ("name", "model_patches"),
        }
        for planned in (task.plan(request()), task.plan(inpaint())):
            profile = set(manifest.profiles[planned["profile"]])
            found = 0
            for node in task.graph(planned).values():
                if node["class_type"] in loaders:
                    field, folder = loaders[node["class_type"]]
                    found += 1
                    with self.subTest(mode=planned["mode"], node=node["class_type"]):
                        self.assertIn(f"{folder}/{node['inputs'][field]}", profile)
            self.assertEqual(found, 4)

    def test_graphs_are_plain_json(self) -> None:
        json.dumps(task.graph(task.plan(request())))
        json.dumps(task.graph(task.plan(inpaint())))


class HostPlanTest(unittest.TestCase):
    def test_the_host_plans_a_staged_request_without_echoing_the_prompt(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        work = temp.path / "in"
        (work / "sources").mkdir(parents=True)
        (work / "sources" / "00.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        inputs = {"mode": "inpaint", "source_asset_id": "asset-a", "prompt": "secret wording", "control_strength": "1", **MASK}
        (work / "inputs.json").write_text(json.dumps(inputs), encoding="utf-8")
        staged = [{"file": "sources/00.png", "ordinal": 0, "kind": "image", "contentType": "image/png", "sizeBytes": 8}]
        (work / "sources.json").write_text(json.dumps(staged), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, "-I", str(RUNNERS / "comfyui-image" / "entrypoint.py"), "plan", "--task", "z-image-edit", "--input-dir", str(work)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), {"task": "z-image-edit", "profile": "z-image-turbo-controlnet"})
        self.assertNotIn("secret wording", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
