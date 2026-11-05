"""minimax-h3 profiles and ComfyUI graphs: the Quality and Turbo profiles, the
frame grid and VRAM reserve, the endpoint-frame and reference graphs, the
ComfyUI flags, and the vendored custom nodes the graphs depend on."""

from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

from tests.support import RUNNERS, load

RUNNER = RUNNERS / "minimax-h3"
if str(RUNNER) not in sys.path:
    sys.path.insert(0, str(RUNNER))

models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

from minimax_h3 import graph, profiles, references  # noqa: E402

QUALITY = profiles.PERFORMANCE_PROFILES["quality"]
TURBO = profiles.PERFORMANCE_PROFILES["turbo"]
NODES = RUNNER / "comfy_nodes" / graph.CUSTOM_NODES
PROMPT = "integrated_multimodal_description: a kite rises over a windy beach"


def ref(index: int, kind: str, role: str) -> references.Reference:
    return references.Reference(f"00000000-0000-4000-8000-{index:012d}", kind, role, index)


def build(profile: profiles.InferenceProfile = QUALITY, mode: str = "text_to_video", staged: tuple = ()) -> dict:
    return graph.build(
        prompt=PROMPT, profile=profile, generation_mode=mode, width=1280, height=736, frames=362, seed=7, staged=staged
    )


class ProfileTest(unittest.TestCase):
    def test_quality_and_turbo_are_the_two_served_profiles(self) -> None:
        self.assertEqual(sorted(profiles.PERFORMANCE_PROFILES), ["quality", "turbo"])
        self.assertEqual((QUALITY.name, QUALITY.steps, QUALITY.sampler), ("native-sage-cab10", 10, "cab-2"))
        self.assertEqual((TURBO.name, TURBO.steps, TURBO.sampler), ("turbo-lightx2v-4step-768p", 4, "euler"))
        self.assertEqual((TURBO.lora_name, TURBO.lora_strength, TURBO.video_shift, TURBO.audio_shift), (profiles.TURBO_LORA, 1.0, 6.0, 3.0))
        self.assertIsNone(QUALITY.lora_name)

    def test_canvases_render_at_736_and_deliver_720p(self) -> None:
        self.assertEqual(profiles.CANVASES["landscape"], profiles.Canvas((1280, 736), (1280, 720)))
        self.assertEqual(profiles.CANVASES["portrait"], profiles.Canvas((736, 1280), (720, 1280)))

    def test_the_vram_reserve_scales_with_the_latent(self) -> None:
        for frames, expected in ((56, 4.0), (175, 6.75), (362, 12.25), (481, 15.75)):
            with self.subTest(frames=frames):
                self.assertEqual(profiles.reserved_vram_gb(TURBO, frames, 1280, 736), expected)
        # CAB keeps earlier denoising state on the GPU, so Quality reserves more.
        self.assertEqual(profiles.reserved_vram_gb(QUALITY, 362, 1280, 736), 16.5)
        self.assertEqual(profiles.reserved_vram_gb(QUALITY, 56, 1280, 736), 4.75)
        with self.assertRaisesRegex(ValueError, "positive"):
            profiles.reserved_vram_gb(QUALITY, 0, 1280, 736)

    def test_each_request_maps_to_one_model_folder_profile(self) -> None:
        self.assertEqual(profiles.model_profile(False, QUALITY), "fl2va")
        self.assertEqual(profiles.model_profile(False, TURBO), "fl2va-turbo")
        self.assertEqual(profiles.model_profile(True, QUALITY), "ref2va")
        with self.assertRaisesRegex(ValueError, "Turbo"):
            profiles.model_profile(True, TURBO)


class GraphTest(unittest.TestCase):
    def test_quality_uses_the_cab_sampler_over_the_low_memory_model(self) -> None:
        nodes = build()
        self.assertEqual(nodes["1"]["inputs"]["unet_name"], profiles.FL2VA_MODEL)
        self.assertEqual(nodes["2"]["inputs"], {"clip_name": profiles.TEXT_ENCODER, "type": "minimax", "device": "default"})
        self.assertEqual(nodes["3"]["inputs"]["vae_name"], profiles.VIDEO_VAE)
        self.assertEqual(nodes["4"]["inputs"]["vae_name"], profiles.AUDIO_VAE)
        self.assertEqual(nodes["5"]["class_type"], "MiniMaxH3ImageToVideo")
        self.assertEqual(
            {key: nodes["5"]["inputs"][key] for key in ("prompt", "width", "height", "length")},
            {"prompt": PROMPT, "width": 1280, "height": 736, "length": 362},
        )
        self.assertEqual(nodes["6"]["inputs"]["noise_seed"], 7)
        self.assertEqual(nodes["8"], {"class_type": graph.CAB_SAMPLER, "inputs": {"order": "CAB-2", "theta": 0.2}})
        self.assertEqual(nodes["9"]["inputs"]["steps"], 10)
        self.assertEqual(nodes["15"], {
            "class_type": graph.LOW_MEMORY,
            "inputs": {"model": ["1", 0], "chunks": 4, "qkv_chunks": 8, "attention_head_chunks": 4, "sequence_threshold": 4096},
        })
        self.assertEqual((nodes["7"]["inputs"]["model"], nodes["9"]["inputs"]["model"]), (["15", 0], ["15", 0]))
        self.assertEqual(nodes["13"]["inputs"], {"images": ["11", 0], "audio": ["12", 0], "fps": 24.0, "bit_depth": 8})
        self.assertEqual(nodes["14"]["inputs"]["codec"], "h264")
        self.assertEqual(nodes["14"]["inputs"]["codec.encoding.crf"], 16.0)
        self.assertNotIn("16", nodes)

    def test_turbo_adds_the_pinned_lora_and_sigma_shift(self) -> None:
        nodes = build(TURBO)
        self.assertEqual(nodes["8"], {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}})
        self.assertEqual(nodes["9"]["inputs"]["steps"], 4)
        self.assertEqual(nodes["16"], {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"model": ["1", 0], "lora_name": profiles.TURBO_LORA, "strength_model": 1.0},
        })
        self.assertEqual(nodes["15"]["inputs"]["model"], ["16", 0])
        self.assertEqual(nodes["17"], {"class_type": "MiniMaxH3SigmaShift", "inputs": {"model": ["15", 0], "shift_video": 6.0, "shift_audio": 3.0}})
        self.assertEqual((nodes["7"]["inputs"]["model"], nodes["9"]["inputs"]["model"]), (["17", 0], ["17", 0]))

    def test_endpoint_frames_feed_the_fl2va_node_by_role(self) -> None:
        staged = ((ref(0, "image", "last_frame"), "ref-00.png"), (ref(1, "image", "first_frame"), "ref-01.png"))
        nodes = build(mode="first_last_frame_to_video", staged=staged)
        self.assertEqual(nodes["1"]["inputs"]["unet_name"], profiles.FL2VA_MODEL)
        self.assertEqual(nodes["20"], {"class_type": "LoadImage", "inputs": {"image": "ref-00.png"}})
        self.assertEqual((nodes["5"]["inputs"]["last_frame"], nodes["5"]["inputs"]["first_frame"]), (["20", 0], ["21", 0]))

    def test_reference_modes_load_images_videos_and_audio_into_ref2va(self) -> None:
        staged = (
            (ref(0, "video", "source_video"), "ref-00.mp4"),
            (ref(1, "image", "subject"), "ref-01.png"),
            (ref(2, "audio", "audio_reuse"), "ref-02.wav"),
        )
        nodes = build(mode="video_edit", staged=staged)
        self.assertEqual(nodes["1"]["inputs"]["unet_name"], profiles.REF2VA_MODEL)
        self.assertEqual(nodes["5"]["class_type"], "MiniMaxH3ReferenceToVideo")
        self.assertEqual((nodes["5"]["inputs"]["audio_vae"], nodes["5"]["inputs"]["ref_image_size"]), (["4", 0], "match"))
        self.assertEqual([nodes[str(node)]["class_type"] for node in range(20, 24)], ["LoadVideo", "GetVideoComponents", "LoadImage", "LoadAudio"])
        self.assertEqual(nodes["5"]["inputs"]["ref_videos.ref_video_0"], ["21", 0])
        self.assertEqual(nodes["5"]["inputs"]["ref_images.ref_image_0"], ["22", 0])
        self.assertEqual(nodes["5"]["inputs"]["ref_audios.ref_audio_0"], ["23", 0])

    def test_turbo_never_builds_a_reference_graph(self) -> None:
        with self.assertRaisesRegex(ValueError, "Turbo"):
            build(TURBO, mode="reference_to_video", staged=((ref(0, "image", "subject"), "ref-00.png"),))

    def test_every_model_a_graph_loads_is_in_its_model_folder_profile(self) -> None:
        manifest = models.load_manifest(RUNNER / "models.json")
        loaders = {"UNETLoader": ("unet_name", "diffusion_models"), "CLIPLoader": ("clip_name", "text_encoders"),
                   "VAELoader": ("vae_name", "vae"), "LoraLoaderModelOnly": ("lora_name", "loras")}
        cases = {"fl2va": build(), "fl2va-turbo": build(TURBO),
                 "ref2va": build(mode="reference_to_video", staged=((ref(0, "image", "style"), "ref-00.png"),))}
        for name, nodes in cases.items():
            used = {f"{loaders[node['class_type']][1]}/{node['inputs'][loaders[node['class_type']][0]]}"
                    for node in nodes.values() if node["class_type"] in loaders}
            with self.subTest(profile=name):
                self.assertEqual(used, set(manifest.profiles[name]))


class ComfyArgsTest(unittest.TestCase):
    def test_only_the_vendored_nodes_load_and_weights_stream_from_disk(self) -> None:
        args = graph.comfy_args()
        self.assertIn("--disable-all-custom-nodes", args)
        self.assertEqual(args[args.index("--whitelist-custom-nodes") + 1], graph.CUSTOM_NODES)
        for flag in ("--enable-dynamic-vram", "--disable-smart-memory", "--fast-disk", "--cache-none", "--use-sage-attention", "--disable-metadata"):
            with self.subTest(flag=flag):
                self.assertIn(flag, args)
        self.assertEqual(args[args.index("--preview-method") + 1], "none")
        for owned in ("--listen", "--reserve-vram", "--lowvram", "--port"):
            self.assertNotIn(owned, args)


class CustomNodeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.init = (NODES / "__init__.py").read_text(encoding="utf-8")
        self.cab = (NODES / "cab_sampler.py").read_text(encoding="utf-8")

    def test_the_package_registers_exactly_the_nodes_the_graphs_use(self) -> None:
        tree = ast.parse(self.init)
        mapping = next(
            node.value for node in tree.body
            if isinstance(node, ast.Assign) and any(getattr(target, "id", "") == "NODE_CLASS_MAPPINGS" for target in node.targets)
        )
        self.assertEqual({key.value for key in mapping.keys}, {graph.LOW_MEMORY, graph.CAB_SAMPLER})

    def test_the_low_memory_patch_keeps_comfy_weight_management_and_out_of_place_rope(self) -> None:
        self.assertIn("comfy.ops.cast_bias_weight(", self.init)
        self.assertIn("comfy.ops.uncast_bias_weight(", self.init)
        self.assertIn("rms_rope_split_half(", self.init)
        self.assertNotIn("rms_rope_split_half_(", self.init)
        self.assertNotIn("module.qkv_proj(token_chunk)", self.init)

    def test_the_adapted_cab_sampler_keeps_its_upstream_notice(self) -> None:
        self.assertIn("ByronLeeeee", self.cab)
        notice = (NODES / "LICENSE-cab-sampler").read_text(encoding="utf-8")
        self.assertIn("MIT License", notice)
        self.assertIn("Copyright (c) 2026 ByronLeeeee", notice)


if __name__ == "__main__":
    unittest.main()
