"""minimax-h3 reference manifests and continuations: the modes and roles ii-os
dispatches, the sources the claim staged, reference durations, the prompt
labels each reference gets, and how a continuation anchors its source."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

from tests.support import RUNNERS, load

RUNNER = RUNNERS / "minimax-h3"
if str(RUNNER) not in sys.path:
    sys.path.insert(0, str(RUNNER))

runner_io = load("runners/common/runner_io.py", "runner_io")

from minimax_h3 import extension, references  # noqa: E402

CONTENT_TYPES = {"image": "image/png", "video": "video/mp4", "audio": "audio/wav"}


def asset(index: int) -> str:
    return f"00000000-0000-4000-8000-{index:012d}"


def manifest(mode: str, *refs: tuple[str, str], **extra: object) -> str:
    value: dict[str, object] = {
        "schema_version": 1,
        "mode": mode,
        "references": [
            {"asset_id": asset(index), "kind": kind, "role": role, "ordinal": index}
            for index, (kind, role) in enumerate(refs)
        ],
    }
    value.update(extra)
    return json.dumps(value)


def source(index: int, kind: str, role: str | None, asset_id: str | None = None) -> runner_io.Source:
    suffix = CONTENT_TYPES[kind].split("/")[1]
    return runner_io.Source(
        path=Path(f"/work/in/sources/{index:02d}.{suffix}"),
        content_type=CONTENT_TYPES[kind],
        kind=kind,
        ordinal=index,
        role=role,
        size_bytes=10,
        asset_id=asset(index) if asset_id is None else asset_id,
    )


EDIT = {"edit_operation": "general_edit", "identity_replacement_consent": False}


class ManifestTest(unittest.TestCase):
    def accepted(self, mode: str, *refs: tuple[str, str], **extra: object) -> references.Manifest:
        return references.parse_manifest(manifest(mode, *refs, **extra), mode)

    def refused(self, mode: str, *refs: tuple[str, str], **extra: object) -> None:
        with self.assertRaises(references.ManifestError):
            references.parse_manifest(manifest(mode, *refs, **extra), mode)

    def test_text_to_video_needs_no_manifest(self) -> None:
        for raw in (None, ""):
            parsed = references.parse_manifest(raw, "text_to_video")
            self.assertEqual((parsed.mode, parsed.references), ("text_to_video", ()))
        self.refused("text_to_video", ("image", "subject"))

    def test_every_other_mode_needs_a_manifest(self) -> None:
        for mode in references.GENERATION_MODES[1:]:
            with self.subTest(mode=mode), self.assertRaisesRegex(references.ManifestError, "reference_manifest"):
                references.parse_manifest(None, mode)

    def test_endpoint_modes_take_exactly_their_frames(self) -> None:
        self.assertEqual(len(self.accepted("first_frame_to_video", ("image", "first_frame")).references), 1)
        self.accepted("last_frame_to_video", ("image", "last_frame"))
        self.accepted("first_last_frame_to_video", ("image", "first_frame"), ("image", "last_frame"))
        self.accepted("first_last_frame_to_video", ("image", "last_frame"), ("image", "first_frame"))
        self.refused("first_frame_to_video", ("image", "last_frame"))
        self.refused("first_frame_to_video", ("image", "first_frame"), ("image", "subject"))
        self.refused("last_frame_to_video")
        self.refused("first_last_frame_to_video", ("image", "first_frame"), ("image", "first_frame"))

    def test_reference_modes_need_their_sources(self) -> None:
        self.accepted("reference_to_video", ("audio", "audio_reference"))
        self.refused("reference_to_video")
        self.accepted("video_continue", ("video", "source_video"), ("image", "subject"))
        self.refused("video_continue", ("video", "motion_reference"))
        self.refused("video_continue", ("video", "source_video"), ("video", "source_video"))
        self.accepted("video_edit", ("video", "source_video"), **EDIT)
        self.refused("video_edit", ("image", "subject"), **EDIT)

    def test_the_manifest_mode_must_be_the_requested_mode(self) -> None:
        with self.assertRaisesRegex(references.ManifestError, "mode"):
            references.parse_manifest(manifest("video_continue", ("video", "source_video")), "reference_to_video")

    def test_entries_are_checked_one_by_one(self) -> None:
        self.refused("reference_to_video", ("video", "subject"))
        self.refused("reference_to_video", ("image", "made_up_role"))
        broken = json.loads(manifest("reference_to_video", ("image", "subject"), ("image", "style")))
        for change in (
            lambda value: value["references"][1].update(ordinal=3),
            lambda value: value["references"][1].update(asset_id=asset(0)),
            lambda value: value["references"][0].update(url="https://storage.example.com/x"),
            lambda value: value.update(schema_version=2),
            lambda value: value.update(extra=True),
            lambda value: value["references"][0].update(asset_id=""),
        ):
            candidate = json.loads(json.dumps(broken))
            change(candidate)
            with self.subTest(candidate=candidate), self.assertRaises(references.ManifestError):
                references.parse_manifest(json.dumps(candidate), "reference_to_video")
        for raw in ("not json", "[]", "x" * 30001):
            with self.subTest(raw=raw[:10]), self.assertRaises(references.ManifestError):
                references.parse_manifest(raw, "reference_to_video")

    def test_count_ceilings_follow_the_model(self) -> None:
        self.accepted("reference_to_video", *[("image", "subject")] * 9, *[("audio", "audio_reference")] * 3)
        self.refused("reference_to_video", *[("image", "subject")] * 10)
        self.refused("reference_to_video", *[("video", "motion_reference")] * 4)
        self.refused("reference_to_video", *[("audio", "audio_reuse")] * 4)
        self.refused("reference_to_video", *[("image", "style")] * 9, *[("audio", "audio_reference")] * 3, ("video", "video_style"))

    def test_video_edit_carries_its_operation_and_consent(self) -> None:
        parsed = self.accepted(
            "video_edit", ("video", "source_video"), ("image", "subject"),
            edit_operation="character_replacement", identity_replacement_consent=True,
        )
        self.assertEqual((parsed.edit_operation, parsed.identity_replacement_consent), ("character_replacement", True))
        self.accepted(
            "video_edit", ("video", "source_video"), ("video", "video_subject"),
            edit_operation="character_replacement", identity_replacement_consent=True,
        )
        self.refused("video_edit", ("video", "source_video"))
        self.refused("video_edit", ("video", "source_video"), edit_operation="paint_it_blue", identity_replacement_consent=False)
        self.refused("video_edit", ("video", "source_video"), edit_operation="general_edit", identity_replacement_consent="yes")
        self.refused(
            "video_edit", ("video", "source_video"), ("image", "subject"),
            edit_operation="character_replacement", identity_replacement_consent=False,
        )
        self.refused(
            "video_edit", ("video", "source_video"),
            edit_operation="character_replacement", identity_replacement_consent=True,
        )
        self.refused("reference_to_video", ("image", "subject"), **EDIT)

    def test_declared_edit_inputs_must_agree_with_the_manifest(self) -> None:
        parsed = self.accepted("video_edit", ("video", "source_video"), **EDIT)
        references.check_declared(parsed, edit_operation="general_edit", consent="false")
        references.check_declared(parsed, edit_operation=None, consent=None)
        with self.assertRaises(references.ManifestError):
            references.check_declared(parsed, edit_operation="object_replacement", consent="false")
        with self.assertRaises(references.ManifestError):
            references.check_declared(parsed, edit_operation="general_edit", consent="true")
        plain = self.accepted("first_frame_to_video", ("image", "first_frame"))
        with self.assertRaises(references.ManifestError):
            references.check_declared(plain, edit_operation="general_edit", consent=None)


class SourcesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.parsed = references.parse_manifest(
            manifest("video_continue", ("video", "source_video"), ("audio", "audio_reuse")), "video_continue"
        )

    def test_the_claim_staged_exactly_the_manifest(self) -> None:
        references.match_sources(self.parsed, [source(0, "video", "source_video"), source(1, "audio", "audio_reuse")])

    def test_any_difference_is_refused(self) -> None:
        cases = {
            "missing": [source(0, "video", "source_video")],
            "reordered": [source(1, "audio", "audio_reuse"), source(0, "video", "source_video")],
            "other asset": [source(0, "video", "source_video"), source(1, "audio", "audio_reuse", asset_id=asset(7))],
            "other role": [source(0, "video", "motion_reference"), source(1, "audio", "audio_reuse")],
            "other kind": [source(0, "video", "source_video"), source(1, "image", "audio_reuse")],
        }
        for label, staged in cases.items():
            with self.subTest(case=label), self.assertRaises(references.ManifestError):
                references.match_sources(self.parsed, staged)


class DurationTest(unittest.TestCase):
    def ref(self, index: int, kind: str, role: str) -> references.Reference:
        return references.Reference(asset(index), kind, role, index)

    def test_each_clip_is_two_to_fifteen_seconds_and_each_kind_totals_fifteen(self) -> None:
        video, audio = self.ref(0, "video", "source_video"), self.ref(1, "audio", "audio_reference")
        references.check_durations([(video, 15.0), (audio, 15.0)])
        references.check_durations([(video, 2.0), (self.ref(2, "video", "motion_reference"), 13.0)])
        for durations in (
            [(video, 1.5)],
            [(video, 15.5)],
            [(video, 8.0), (self.ref(2, "video", "motion_reference"), 8.0)],
            [(audio, 10.0), (self.ref(2, "audio", "audio_reuse"), 6.0)],
        ):
            with self.subTest(durations=durations), self.assertRaises(references.ManifestError):
                references.check_durations(durations)


class PromptTest(unittest.TestCase):
    PROMPT = "a paper lantern drifts over a quiet harbor at dusk"

    def test_endpoint_modes_label_the_prompt_once(self) -> None:
        labelled = references.prepare_prompt(self.PROMPT, "text_to_video", ())
        self.assertEqual(labelled, "integrated_multimodal_description: " + self.PROMPT)
        self.assertEqual(references.prepare_prompt(labelled, "first_frame_to_video", ()), labelled)

    def test_reference_modes_name_each_reference_by_kind_and_role(self) -> None:
        parsed = references.parse_manifest(
            manifest("video_edit", ("video", "source_video"), ("image", "subject"), ("image", "style"), ("audio", "audio_reuse"), **EDIT),
            "video_edit",
        )
        prompt = references.prepare_prompt(self.PROMPT, "video_edit", parsed.references)
        self.assertTrue(prompt.startswith("subject_definitions:\n<Video 1> is the source timeline to edit.\n"))
        self.assertIn("<Picture 1> defines the subject identity and visible appearance.", prompt)
        self.assertIn("<Picture 2> defines the target visual style.", prompt)
        self.assertIn("<Audio 1> is copied or retained as the requested target audio.", prompt)
        self.assertTrue(prompt.endswith("\n\n" + self.PROMPT))

    def test_an_existing_subject_heading_is_reused(self) -> None:
        parsed = references.parse_manifest(manifest("video_continue", ("video", "source_video")), "video_continue")
        prompt = references.prepare_prompt("subject_definitions:\nsummary:\nKeep walking.", "video_continue", parsed.references)
        self.assertEqual(prompt.count("subject_definitions:"), 1)
        self.assertTrue(prompt.startswith("subject_definitions:\n<Video 1> is the source whose final moment begins the continuation."))


class FrameGridTest(unittest.TestCase):
    def test_durations_round_up_onto_the_latent_grid(self) -> None:
        for seconds, frames in ((2.0, 56), (4.0, 107), (5.0, 124), (15.0, 362), (20.0, 481)):
            with self.subTest(seconds=seconds):
                self.assertEqual(extension.aligned_frame_count(seconds), frames)
                self.assertEqual(frames % 17, 5)

    def test_the_guide_node_crops_an_anchor_down_to_the_same_grid(self) -> None:
        self.assertEqual(extension.anchored_guide_frames(120), 107)
        self.assertEqual(extension.anchored_guide_frames(107), 107)
        self.assertEqual(extension.anchored_guide_frames(22), 22)
        self.assertEqual(extension.anchored_guide_frames(4), 1)


class ContinuationTest(unittest.TestCase):
    def test_the_render_covers_the_finished_video(self) -> None:
        self.assertEqual(extension.validate_extension(5.0, 15.0), 362)

    def test_a_continuation_must_add_two_seconds(self) -> None:
        for source_seconds in (14.0, 15.0):
            with self.subTest(source=source_seconds), self.assertRaisesRegex(ValueError, "at least 2 seconds"):
                extension.validate_extension(source_seconds, 15.0)

    def test_a_source_too_short_to_anchor_is_refused(self) -> None:
        with self.assertRaisesRegex(ValueError, "too short to anchor"):
            extension.validate_extension(0.1, 15.0)

    def test_the_source_is_anchored_at_frame_zero_with_its_sound(self) -> None:
        graph = {
            "3": {"class_type": "VAELoader", "inputs": {}},
            "5": {"class_type": "MiniMaxH3ReferenceToVideo", "inputs": {"length": 1}},
            "7": {"class_type": "BasicGuider", "inputs": {"conditioning": ["5", 0]}},
        }
        self.assertEqual(extension.add_guide_graph(graph, "ref-00.mp4", 362, 20), 23)
        self.assertEqual(graph["20"], {"class_type": "LoadVideo", "inputs": {"file": "ref-00.mp4"}})
        self.assertEqual(graph["21"]["inputs"]["video"], ["20", 0])
        guide = graph["22"]
        self.assertEqual(guide["class_type"], "MiniMaxH3AddGuide")
        self.assertEqual(guide["inputs"]["frame_idx"], 0)
        self.assertEqual((guide["inputs"]["image"], guide["inputs"]["audio"]), (["21", 0], ["21", 1]))
        self.assertEqual((guide["inputs"]["vae"], guide["inputs"]["audio_vae"]), (["3", 0], ["4", 0]))
        self.assertEqual(graph["7"]["inputs"]["conditioning"], ["22", 0])
        self.assertEqual(graph["5"]["inputs"]["length"], 362)


if __name__ == "__main__":
    unittest.main()
