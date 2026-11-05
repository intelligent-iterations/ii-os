"""chatterbox-narration text-to-speech: request validation, the voice-clone
consent rule, the ffmpeg commands, and the model profile."""

from __future__ import annotations

from pathlib import Path
import subprocess
import unittest

from tests.support import RUNNERS, KIT_ROOT, TempDir, load

runner_io = load("runners/common/runner_io.py", "runner_io")
task = load("runners/chatterbox-narration/tasks/text_to_speech.py", "kit_chatterbox_narration_text_to_speech")
models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")

TEXT = "The lighthouse keeper counted the ships."


def reference(*, kind: str = "audio", size: int = 1024, asset_id: str = "asset-1") -> runner_io.Source:
    return runner_io.Source(
        path=Path("/work/in/sources/00.wav"),
        content_type="audio/wav" if kind == "audio" else "image/png",
        kind=kind,
        ordinal=0,
        role="audio_reference",
        size_bytes=size,
        asset_id=asset_id,
    )


def request(sources: list | None = None, **inputs: str) -> runner_io.Request:
    return runner_io.Request(inputs={"text": TEXT, **inputs}, sources=sources or [])


class PlanTest(unittest.TestCase):
    def test_plain_narration_uses_the_turbo_profile(self) -> None:
        plan = task.plan(request(voice_model="chatterbox-turbo", language="English", seed="7"))
        self.assertEqual(plan["profile"], "chatterbox-turbo")
        self.assertEqual(plan["text"], TEXT)
        self.assertEqual(plan["seed"], 7)
        self.assertIsNone(plan["reference"])

    def test_defaults_when_optional_inputs_are_absent(self) -> None:
        plan = task.plan(request())
        self.assertEqual(plan["voice_model"], "chatterbox-turbo")
        self.assertEqual(plan["language"], "English")
        self.assertGreater(plan["seed"], 0)

    def test_text_is_required_and_bounded(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "text is required"):
            task.plan(request(text="   "))
        with self.assertRaisesRegex(runner_io.RequestError, "text is longer than 6000"):
            task.plan(request(text="a" * 6001))
        self.assertEqual(len(task.plan(request(text="a" * 6000))["text"]), 6000)

    def test_refusals_never_echo_the_text(self) -> None:
        secret = "a confidential sentence " * 300
        with self.assertRaises(runner_io.RequestError) as caught:
            task.plan(request(text=secret))
        self.assertNotIn("confidential", str(caught.exception))

    def test_other_voice_models_languages_and_seeds_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "voice_model"):
            task.plan(request(voice_model="chatterbox-multilingual"))
        with self.assertRaisesRegex(runner_io.RequestError, "language"):
            task.plan(request(language="x" * 33))
        for seed in ("-1", "1.5", "seven"):
            with self.subTest(seed=seed), self.assertRaisesRegex(runner_io.RequestError, "seed"):
                task.plan(request(seed=seed))

    def test_a_whole_number_seed_from_the_catalog_is_accepted(self) -> None:
        self.assertEqual(task.plan(request(seed="42.0"))["seed"], 42)

    def test_inputs_the_catalog_does_not_declare_are_refused(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "exaggeration"):
            task.plan(request(exaggeration="0.5"))


class VoiceReferenceTest(unittest.TestCase):
    def test_a_consented_reference_is_planned(self) -> None:
        plan = task.plan(request([reference()], voice_reference_asset_id="asset-1", voice_clone_consent="true"))
        self.assertEqual(plan["reference"], "/work/in/sources/00.wav")

    def test_a_reference_without_consent_is_refused(self) -> None:
        for consent in ({}, {"voice_clone_consent": "false"}):
            with self.subTest(consent=consent), self.assertRaisesRegex(runner_io.RequestError, "voice_clone_consent"):
                task.plan(request([reference()], voice_reference_asset_id="asset-1", **consent))

    def test_consent_is_checked_before_anything_else_about_the_reference(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "voice_clone_consent"):
            task.plan(request([], voice_reference_asset_id="asset-1"))

    def test_the_reference_must_have_been_staged(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "not staged"):
            task.plan(request([], voice_reference_asset_id="asset-1", voice_clone_consent="true"))

    def test_the_staged_reference_must_be_the_named_asset(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "voice_reference_asset_id"):
            task.plan(request([reference(asset_id="asset-2")], voice_reference_asset_id="asset-1", voice_clone_consent="true"))

    def test_a_staged_source_needs_a_named_reference(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "voice_reference_asset_id"):
            task.plan(request([reference()]))

    def test_only_one_audio_reference_is_read(self) -> None:
        with self.assertRaisesRegex(runner_io.RequestError, "audio"):
            task.plan(request([reference(kind="image")], voice_reference_asset_id="asset-1", voice_clone_consent="true"))
        two = [reference(), runner_io.Source(Path("/work/in/sources/01.wav"), "audio/wav", "audio", 1, None, 10, "asset-3")]
        with self.assertRaisesRegex(runner_io.RequestError, "audio"):
            task.plan(request(two, voice_reference_asset_id="asset-1", voice_clone_consent="true"))

    def test_an_oversized_reference_is_refused(self) -> None:
        big = reference(size=50 * 1024 * 1024 + 1)
        with self.assertRaisesRegex(runner_io.RequestError, "50 MB"):
            task.plan(request([big], voice_reference_asset_id="asset-1", voice_clone_consent="true"))


class AudioCommandTest(unittest.TestCase):
    def test_the_reference_is_cut_to_mono_24k_without_metadata(self) -> None:
        command = task.reference_command(Path("/in/00.m4a"), Path("/tmp/ref.wav"))
        self.assertEqual(command[0], "ffmpeg")
        self.assertIn("-nostdin", command)
        for flag, value in (("-t", "30"), ("-ar", "24000"), ("-ac", "1"), ("-map_metadata", "-1")):
            self.assertEqual(command[command.index(flag) + 1], value)
        self.assertEqual(command[-1], "/tmp/ref.wav")

    def test_the_mp3_is_lame_vbr(self) -> None:
        command = task.mp3_command(Path("/out/narration.wav"), Path("/out/narration.mp3"))
        self.assertEqual(command[command.index("-codec:a") + 1], "libmp3lame")
        self.assertEqual(command[command.index("-q:a") + 1], "2")
        self.assertEqual(command[-1], "/out/narration.mp3")

    def test_a_short_reference_is_refused_after_conversion(self) -> None:
        calls: list[list[str]] = []

        def fake(command: list[str], **_: object) -> subprocess.CompletedProcess:
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, stdout="4.9\n" if command[0] == "ffprobe" else "")

        temp = TempDir()
        self.addCleanup(temp.cleanup)
        with self.assertRaisesRegex(runner_io.RequestError, "longer than 5 seconds"):
            task.prepare_reference(Path("/in/00.wav"), temp.path, run=fake)
        self.assertEqual([call[0] for call in calls], ["ffmpeg", "ffprobe"])

    def test_a_long_enough_reference_is_returned(self) -> None:
        def fake(command: list[str], **_: object) -> subprocess.CompletedProcess:
            return subprocess.CompletedProcess(command, 0, stdout="12.25\n" if command[0] == "ffprobe" else "")

        temp = TempDir()
        self.addCleanup(temp.cleanup)
        self.assertEqual(task.prepare_reference(Path("/in/00.wav"), temp.path, run=fake), temp.path / "voice-reference.wav")

    def test_sampling_matches_the_turbo_defaults(self) -> None:
        self.assertEqual(task.SAMPLING, {"temperature": 0.8, "top_p": 0.95, "top_k": 1000, "repetition_penalty": 1.2})


class ModelProfileTest(unittest.TestCase):
    def test_the_profile_lists_every_file_from_local_reads(self) -> None:
        manifest = models.load_manifest(RUNNERS / "chatterbox-narration" / "models.json")
        profile = set(manifest.profiles[task.plan(request())["profile"]])
        for name in task.MODEL_FILES:
            self.assertIn(f"chatterbox-turbo/{name}", profile)
        for path in profile:
            item = manifest.files[path]
            self.assertIn("/resolve/749d1c1a46eb10492095d68fbcf55691ccf137cd/", item.source)
            self.assertEqual(item.license, "MIT")

    def test_the_workflow_reads_one_audio_source_and_publishes_audio(self) -> None:
        text = (KIT_ROOT / ".github" / "workflows" / "narration-generation.yml").read_text(encoding="utf-8")
        self.assertIn('max-sources: "1"', text)
        self.assertIn("source-kinds: audio", text)
        self.assertIn("allowed-content-types: audio/mpeg,audio/wav", text)
        self.assertIn('max-bytes: "524288000"', text)
        self.assertIn("RUNNER_NAME: chatterbox-narration", text)
        self.assertIn("RUNNER_TASK: text-to-speech", text)
        for name in ("text", "voice_model", "language", "seed", "voice_reference_asset_id", "voice_clone_consent"):
            self.assertIn(f"\n      {name}:\n", text)


if __name__ == "__main__":
    unittest.main()
