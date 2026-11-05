"""acestep-song text-to-song: request validation, the public render profiles,
the ACE-Step release payload, the bounded retry, and the model profiles."""

from __future__ import annotations

from pathlib import Path
import unittest

from tests.support import RUNNERS, KIT_ROOT, load

runner_io = load("runners/common/runner_io.py", "runner_io")
task = load("runners/acestep-song/tasks/text_to_song.py", "kit_acestep_song_text_to_song")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

PROMPT = "A luminous synth-pop anthem"


def request(**inputs: str) -> runner_io.Request:
    values = {
        "prompt": PROMPT,
        "lyrics": "[Verse]\nWe begin again",
        "instrumental": "false",
        "duration_seconds": "60",
        "generation_profile": "quality-60",
        "bpm": "118",
        "key_scale": "C Major",
        "time_signature": "4",
        "vocal_language": "en",
        "seed": "42",
    }
    values.update(inputs)
    return runner_io.Request(inputs={key: value for key, value in values.items() if value is not None}, sources=[])


class PlanTest(unittest.TestCase):
    def test_public_profiles_are_the_model_profiles(self) -> None:
        self.assertEqual(sorted(task.PROFILES), ["draft-120", "quality-60"])
        self.assertEqual(task.plan(request())["profile"], "quality-60")
        self.assertEqual(task.plan(request(generation_profile="draft-120", duration_seconds="120"))["profile"], "draft-120")

    def test_an_absent_profile_means_the_draft(self) -> None:
        plan = task.plan(request(generation_profile=None, duration_seconds=None))
        self.assertEqual(plan["profile"], "draft-120")
        self.assertEqual(plan["duration_seconds"], 120)

    def test_unknown_profiles_are_refused(self) -> None:
        for name in ("studio-180", "best-60", "xl-sft"):
            with self.subTest(name=name), self.assertRaisesRegex(runner_io.RequestError, "generation_profile"):
                task.plan(request(generation_profile=name))

    def test_each_profile_caps_its_duration(self) -> None:
        self.assertEqual(task.plan(request(generation_profile="draft-120", duration_seconds="120"))["duration_seconds"], 120)
        self.assertEqual(task.plan(request(duration_seconds="60.0"))["duration_seconds"], 60)
        for profile, value in (("draft-120", "121"), ("quality-60", "61"), ("quality-60", "9"), ("draft-120", "30.5")):
            with self.subTest(profile=profile, value=value), self.assertRaisesRegex(runner_io.RequestError, "duration_seconds"):
                task.plan(request(generation_profile=profile, duration_seconds=value))

    def test_ranges_are_enforced(self) -> None:
        for field, value in (("bpm", "29"), ("bpm", "301"), ("seed", "-1"), ("seed", str(2**31))):
            with self.subTest(field=field, value=value), self.assertRaisesRegex(runner_io.RequestError, field):
                task.plan(request(**{field: value}))
        plan = task.plan(request(bpm="", seed=""))
        self.assertIsNone(plan["bpm"])
        self.assertIsNone(plan["seed"])

    def test_key_scale_is_normalized_and_validated(self) -> None:
        self.assertEqual(task.plan(request(key_scale="C# Major"))["key_scale"], "C# major")
        self.assertEqual(task.plan(request(key_scale=""))["key_scale"], "")
        with self.assertRaisesRegex(runner_io.RequestError, "key_scale"):
            task.plan(request(key_scale="H harmonic minor"))

    def test_time_signature_and_language_follow_the_model_contract(self) -> None:
        self.assertEqual(task.plan(request(time_signature=""))["time_signature"], "")
        with self.assertRaisesRegex(runner_io.RequestError, "time_signature"):
            task.plan(request(time_signature="5"))
        self.assertEqual(task.plan(request(vocal_language=""))["vocal_language"], "unknown")
        self.assertEqual(task.plan(request(vocal_language="YUE"))["vocal_language"], "yue")
        with self.assertRaisesRegex(runner_io.RequestError, "vocal_language"):
            task.plan(request(vocal_language="xx"))

    def test_text_is_required_bounded_and_never_echoed(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "prompt is required"):
            task.plan(request(prompt=" "))
        with self.assertRaises(runner_io.RequestError) as caught:
            task.plan(request(prompt="secret chorus " * 400))
        self.assertNotIn("secret", str(caught.exception))
        with self.assertRaisesRegex(runner_io.RequestError, "lyrics"):
            task.plan(request(lyrics="x" * 30001))

    def test_undeclared_inputs_and_sources_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "model"):
            task.plan(request(model="xl-sft"))
        with self.assertRaisesRegex(runner_io.RequestError, "source"):
            task.plan(runner_io.Request(inputs=request().inputs, sources=[object()]))  # type: ignore[list-item]

    def test_redaction_covers_the_prompt_and_every_lyric_line(self) -> None:
        plan = task.plan(request(prompt="private song prompt", lyrics="first private line\nsecond private line\nla"))
        values = task.redaction_values(plan)
        for value in ("private song prompt", "first private line", "second private line"):
            self.assertIn(value, values)
        self.assertNotIn("la", values)


class PayloadTest(unittest.TestCase):
    def test_quality_profile_uses_the_planner_and_structured_lyrics(self) -> None:
        payload = task.release_payload(task.plan(request()), token="secret", seed=42)
        self.assertEqual(payload["model"], "acestep-v15-xl-turbo")
        self.assertEqual(payload["lm_model_path"], "acestep-5Hz-lm-4B")
        self.assertEqual(payload["lm_backend"], "vllm")
        self.assertEqual((payload["inference_steps"], payload["guidance_scale"], payload["shift"]), (8, 1.0, 3.0))
        self.assertEqual(payload["audio_format"], "wav")
        self.assertTrue(payload["thinking"])
        self.assertTrue(payload["use_format"])
        self.assertTrue(payload["constrained_decoding"])
        self.assertEqual((payload["seed"], payload["use_random_seed"]), (42, False))
        self.assertEqual(payload["ai_token"], "secret")

    def test_draft_profile_is_the_lightweight_long_render(self) -> None:
        plan = task.plan(request(generation_profile="draft-120", duration_seconds="120", lyrics=""))
        payload = task.release_payload(plan, token="secret", seed=7)
        self.assertEqual(payload["model"], "acestep-v15-xl-turbo")
        self.assertEqual(payload["audio_duration"], 120)
        self.assertFalse(payload["thinking"])
        self.assertFalse(payload["sample_mode"])
        self.assertEqual(payload["prompt"], PROMPT)
        self.assertNotIn("lm_model_path", payload)
        for flag in ("constrained_decoding", "use_cot_caption", "use_cot_language"):
            self.assertFalse(payload[flag])

    def test_blank_lyrics_let_the_planner_write_the_song(self) -> None:
        payload = task.release_payload(task.plan(request(lyrics="")), token="t", seed=1)
        self.assertTrue(payload["sample_mode"])
        self.assertEqual(payload["sample_query"], PROMPT)
        self.assertEqual(payload["prompt"], "")

    def test_plain_lyrics_do_not_enable_format_mode(self) -> None:
        payload = task.release_payload(task.plan(request(lyrics="We begin again\nUnder neon skies")), token="t", seed=1)
        self.assertEqual(payload["lyrics"], "We begin again\nUnder neon skies")
        self.assertFalse(payload["use_format"])
        self.assertFalse(payload["sample_mode"])

    def test_instrumental_uses_the_official_marker(self) -> None:
        payload = task.release_payload(task.plan(request(lyrics="ignored", instrumental="true")), token="t", seed=1)
        self.assertEqual(payload["lyrics"], "[Instrumental]")
        self.assertFalse(payload["sample_mode"])
        self.assertFalse(payload["use_format"])

    def test_auto_metadata_passes_through(self) -> None:
        plan = task.plan(request(time_signature="", vocal_language="unknown", key_scale="", bpm=""))
        payload = task.release_payload(plan, token="t", seed=1)
        self.assertEqual((payload["time_signature"], payload["vocal_language"], payload["key_scale"]), ("", "unknown", ""))
        self.assertIsNone(payload["bpm"])


class FakeClient:
    def __init__(self) -> None:
        self.payloads: list[dict] = []

    def release(self, payload: dict) -> str:
        self.payloads.append(payload)
        return f"task-{len(self.payloads)}"

    def wait_for_result(self, task_id: str, *, timeout: float) -> str:
        return f"/v1/audio?path=/tmp/{task_id}.wav"

    def download(self, audio_url: str, destination: Path) -> None:
        self.downloaded = (audio_url, destination)


class Rejected(Exception):
    pass


class RetryTest(unittest.TestCase):
    def test_a_random_seed_gets_one_retry_after_a_rejected_waveform(self) -> None:
        client = FakeClient()
        outcomes = [Rejected("noise-like"), {"rms": 0.2}]

        def validate(path: Path, *, expected_duration_seconds: float) -> dict:
            outcome = outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome

        seeds = iter([101, 202])
        seed, metrics = task.generate_publishable_wav(
            client, task.plan(request(seed="")), Path("song.wav"), token="t",
            validate=validate, rejected=Rejected, random_seed=lambda: next(seeds),
        )
        self.assertEqual((seed, metrics), (202, {"rms": 0.2}))
        self.assertEqual([payload["seed"] for payload in client.payloads], [101, 202])

    def test_an_explicit_seed_is_never_changed(self) -> None:
        client = FakeClient()

        def validate(path: Path, *, expected_duration_seconds: float) -> dict:
            raise Rejected("silent")

        with self.assertRaisesRegex(Rejected, "silent"):
            task.generate_publishable_wav(
                client, task.plan(request(seed="42")), Path("song.wav"), token="t",
                validate=validate, rejected=Rejected, random_seed=lambda: 7,
            )
        self.assertEqual([payload["seed"] for payload in client.payloads], [42])


class ModelProfileTest(unittest.TestCase):
    def test_every_profile_names_the_folders_ace_step_loads(self) -> None:
        manifest = models.load_manifest(RUNNERS / "acestep-song" / "models.json")
        self.assertEqual(sorted(manifest.profiles), sorted(task.PROFILES))
        for name, profile in task.PROFILES.items():
            folders = {path.split("/", 1)[0] for path in manifest.profiles[name]}
            needed = {profile.dit, "vae", "Qwen3-Embedding-0.6B", "acestep-v15-turbo", "acestep-5Hz-lm-1.7B"}
            if profile.lm:
                needed.add(profile.lm)
            with self.subTest(profile=name):
                self.assertEqual(folders, needed)
                self.assertIn(f"{profile.dit}/silence_latent.pt", manifest.profiles[name])
                self.assertFalse(any(path.endswith(".py") for path in manifest.profiles[name]))

    def test_every_file_is_pinned_to_a_commit_and_mit(self) -> None:
        manifest = models.load_manifest(RUNNERS / "acestep-song" / "models.json")
        for item in manifest.files.values():
            with self.subTest(path=item.path):
                self.assertRegex(item.source, r"^https://huggingface\.co/ACE-Step/[A-Za-z0-9.-]+/resolve/[0-9a-f]{40}/")
                self.assertTrue(item.license.startswith("MIT"))
                self.assertIsNotNone(item.size_bytes)
                self.assertIsNotNone(item.sha256)

    def test_the_workflow_reads_no_sources_and_publishes_audio(self) -> None:
        text = (KIT_ROOT / ".github" / "workflows" / "acestep-song-generation.yml").read_text(encoding="utf-8")
        self.assertIn('max-sources: "0"', text)
        self.assertIn("allowed-content-types: audio/mpeg,audio/wav", text)
        self.assertIn('max-bytes: "1073741824"', text)
        self.assertIn("RUNNER_NAME: acestep-song", text)
        self.assertIn("RUNNER_TASK: text-to-song", text)
        for name in task.INPUTS:
            self.assertIn(f"\n      {name}:\n", text)


if __name__ == "__main__":
    unittest.main()
