"""acestep-song loopback ACE-Step API server: the writable checkpoints layout over
the read-only model folder, the server environment, the HTTP client, and the
redacted failure excerpt."""

from __future__ import annotations

import json
import os
from pathlib import Path
import unittest

from tests.support import FakeResponse, RecordingOpener, TempDir, json_body, load

server = load("runners/acestep-song/acestep_song/server.py", "kit_acestep_song_server")

BASE = "http://127.0.0.1:43123"


class Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        self.now += 1.0
        return self.now


def client(responses: list) -> tuple[object, RecordingOpener]:
    opener = RecordingOpener(responses)
    value = server.AceStepClient(BASE, "token-123", opener=opener, sleep=lambda _: None, clock=Clock(), redact=("private lyric line",))
    return value, opener


class CheckpointLayoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.addCleanup(self.temp.cleanup)
        root = self.temp.path
        self.models = root / "models"
        for folder, names in {
            "acestep-v15-xl-turbo": ("config.json", "model.safetensors.index.json", "silence_latent.pt", "modeling_acestep_v15_xl_turbo.py"),
            "vae": ("config.json", "diffusion_pytorch_model.safetensors"),
            "Qwen3-Embedding-0.6B": ("model.safetensors",),
        }.items():
            (self.models / folder).mkdir(parents=True)
            for name in names:
                (self.models / folder / name).write_text(f"{folder}/{name}")
        (self.models / ".cache").mkdir()
        self.code = root / "ace" / "acestep" / "models" / "xl_turbo"
        self.code.mkdir(parents=True)
        for name in ("__init__.py", "configuration_acestep_v15.py", "modeling_acestep_v15_xl_turbo.py"):
            (self.code / name).write_text(f"pinned {name}")
        self.target = root / "tmp" / "acestep" / "checkpoints"

    def test_the_dit_folder_gets_the_pinned_code_and_links_to_the_weights(self) -> None:
        server.link_checkpoints(self.models, self.target, dit="acestep-v15-xl-turbo", code_dir=self.code)
        dit = self.target / "acestep-v15-xl-turbo"
        self.assertTrue(dit.is_dir() and not dit.is_symlink())
        self.assertEqual(os.readlink(dit / "silence_latent.pt"), str(self.models / "acestep-v15-xl-turbo" / "silence_latent.pt"))
        self.assertEqual((dit / "modeling_acestep_v15_xl_turbo.py").read_text(), "pinned modeling_acestep_v15_xl_turbo.py")
        self.assertFalse((dit / "modeling_acestep_v15_xl_turbo.py").is_symlink())
        self.assertTrue((dit / "configuration_acestep_v15.py").is_file())
        self.assertFalse((dit / "__init__.py").exists())

    def test_other_folders_are_linked_whole_and_hidden_entries_skipped(self) -> None:
        server.link_checkpoints(self.models, self.target, dit="acestep-v15-xl-turbo", code_dir=self.code)
        self.assertEqual(os.readlink(self.target / "vae"), str(self.models / "vae"))
        self.assertTrue((self.target / "Qwen3-Embedding-0.6B" / "model.safetensors").is_file())
        self.assertFalse((self.target / ".cache").exists())

    def test_a_missing_dit_or_code_folder_fails(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "acestep-v15-xl-sft"):
            server.link_checkpoints(self.models, self.target, dit="acestep-v15-xl-sft", code_dir=self.code)
        with self.assertRaisesRegex(RuntimeError, "model code"):
            server.link_checkpoints(self.models, self.target / "x", dit="acestep-v15-xl-turbo", code_dir=self.code / "missing")

    def test_writable_targets_must_be_symlinks_into_tmp(self) -> None:
        link = self.temp.path / "checkpoints"
        link.symlink_to("/tmp/acestep/checkpoints")
        self.assertEqual(server.writable_target(link), Path("/tmp/acestep/checkpoints"))
        elsewhere = self.temp.path / "elsewhere"
        elsewhere.symlink_to("/models")
        plain = self.temp.path / "plain"
        plain.mkdir()
        for path in (elsewhere, plain):
            with self.subTest(path=path.name), self.assertRaisesRegex(RuntimeError, "/tmp"):
                server.writable_target(path)


class ServerProcessTest(unittest.TestCase):
    def test_the_environment_is_offline_and_pinned_to_the_profile(self) -> None:
        env = server.server_environment(
            {"PATH": "/usr/bin", "ACESTEP_OFFLOAD_TO_CPU": "true", "ACESTEP_CONFIG_PATH2": "acestep-v15-base"},
            token="token-123", port=43123, dit="acestep-v15-xl-turbo", lm="acestep-5Hz-lm-4B",
            checkpoints=Path("/tmp/acestep/checkpoints"), tmp_dir=Path("/tmp/ii-os-scratch/acestep/tmp"),
        )
        self.assertEqual(env["PATH"], "/usr/bin")
        self.assertNotIn("ACESTEP_CONFIG_PATH2", env)
        expected = {
            "ACESTEP_API_KEY": "token-123", "ACESTEP_API_HOST": "127.0.0.1", "ACESTEP_API_PORT": "43123",
            "ACESTEP_CONFIG_PATH": "acestep-v15-xl-turbo", "ACESTEP_INIT_LLM": "true",
            "ACESTEP_LM_MODEL_PATH": "acestep-5Hz-lm-4B", "ACESTEP_LM_BACKEND": "vllm", "ACESTEP_DEVICE": "cuda",
            "ACESTEP_OFFLOAD_TO_CPU": "false", "ACESTEP_LM_OFFLOAD_TO_CPU": "false", "ACESTEP_OFFLOAD_DIT_TO_CPU": "false",
            "ACESTEP_CHECKPOINTS_DIR": "/tmp/acestep/checkpoints", "ACESTEP_TMPDIR": "/tmp/ii-os-scratch/acestep/tmp",
            "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
        }
        for key, value in expected.items():
            self.assertEqual(env[key], value, key)

    def test_without_a_planner_the_lm_stays_unloaded(self) -> None:
        env = server.server_environment({}, token="t", port=1, dit="acestep-v15-xl-turbo", lm=None,
                                        checkpoints=Path("/tmp/c"), tmp_dir=Path("/tmp/t"))
        self.assertEqual((env["ACESTEP_INIT_LLM"], env["ACESTEP_LM_MODEL_PATH"]), ("false", ""))
        self.assertNotIn("--init-llm", server.server_command(Path("/venv/python"), 1, lm=None))

    def test_the_api_key_never_appears_on_the_command_line(self) -> None:
        command = server.server_command(Path("/venv/python"), 43123, lm="acestep-5Hz-lm-4B")
        self.assertEqual(command[:3], ["/venv/python", "-m", "acestep.api_server"])
        self.assertEqual(command[command.index("--host") + 1], "127.0.0.1")
        self.assertEqual(command[command.index("--lm-model-path") + 1], "acestep-5Hz-lm-4B")
        self.assertFalse(any("api-key" in part or "token" in part for part in command))


class ClientTest(unittest.TestCase):
    def test_ready_once_the_expected_models_are_loaded(self) -> None:
        loading = {"data": {"models_initialized": False}}
        ready = {"data": {"models_initialized": True, "llm_initialized": True, "loaded_model": "acestep-v15-xl-turbo", "loaded_lm_model": "acestep-5Hz-lm-4B"}}
        value, opener = client([FakeResponse(200, loading), OSError("refused"), FakeResponse(200, ready)])
        value.wait_until_ready(dit="acestep-v15-xl-turbo", lm="acestep-5Hz-lm-4B", timeout=60, alive=lambda: True)
        self.assertEqual(opener.requests[-1]["url"], f"{BASE}/health")
        self.assertEqual(opener.requests[-1]["headers"]["authorization"], "Bearer token-123")

    def test_a_wrong_model_or_a_dead_server_fails(self) -> None:
        wrong = {"data": {"models_initialized": True, "loaded_model": "acestep-v15-turbo"}}
        value, _ = client([FakeResponse(200, wrong)])
        with self.assertRaisesRegex(RuntimeError, "unexpected DiT"):
            value.wait_until_ready(dit="acestep-v15-xl-turbo", lm=None, timeout=60, alive=lambda: True)
        value, _ = client([])
        with self.assertRaisesRegex(RuntimeError, "exited"):
            value.wait_until_ready(dit="acestep-v15-xl-turbo", lm=None, timeout=60, alive=lambda: False)

    def test_release_and_result(self) -> None:
        result = json.dumps([{"file": "/v1/audio?path=%2Ftmp%2Fa.wav"}])
        value, opener = client([
            FakeResponse(200, {"data": {"task_id": "task-1"}}),
            FakeResponse(200, {"data": [{"status": 0}]}),
            FakeResponse(200, {"data": [{"status": 1, "result": result}]}),
        ])
        self.assertEqual(value.release({"ai_token": "token-123", "prompt": "x"}), "task-1")
        self.assertEqual(value.wait_for_result("task-1", timeout=60), "/v1/audio?path=%2Ftmp%2Fa.wav")
        self.assertEqual(opener.requests[0]["url"], f"{BASE}/release_task")
        self.assertEqual(json_body(opener.requests[1]), {"ai_token": "token-123", "task_id_list": ["task-1"]})

    def test_a_failed_task_reports_only_redacted_error_fields(self) -> None:
        nested = json.dumps([{"file": "", "stage": "failed", "error": "boom near private lyric line", "lyrics": "private lyric line"}])
        value, _ = client([FakeResponse(200, {"data": [{"status": 2, "result": nested, "progress_text": "decoding"}]})])
        with self.assertRaises(RuntimeError) as caught:
            value.wait_for_result("task-1", timeout=60)
        message = str(caught.exception)
        self.assertIn("boom near [redacted]", message)
        self.assertIn("failed", message)
        self.assertNotIn("private lyric line", message)

    def test_downloads_only_from_the_loopback_server(self) -> None:
        temp = TempDir()
        self.addCleanup(temp.cleanup)
        value, opener = client([FakeResponse(200, b"RIFF....WAVE")])
        value.download("/v1/audio?path=%2Ftmp%2Fa.wav", temp.path / "song.wav")
        self.assertEqual((temp.path / "song.wav").read_bytes(), b"RIFF....WAVE")
        self.assertEqual(opener.requests[0]["url"], f"{BASE}/v1/audio?path=%2Ftmp%2Fa.wav")
        for url in ("http://example.com/a.wav", "//example.com/a.wav"):
            with self.subTest(url=url), self.assertRaisesRegex(RuntimeError, "loopback"):
                value.download(url, temp.path / "other.wav")
        value, _ = client([FakeResponse(200, b"")])
        with self.assertRaisesRegex(RuntimeError, "empty"):
            value.download("/v1/audio?path=x", temp.path / "empty.wav")


class LogExcerptTest(unittest.TestCase):
    def test_only_redacted_diagnostic_lines_are_kept(self) -> None:
        log = "\n".join([
            "2026-11-04 | INFO | generate_music caption='private song prompt'",
            "Traceback (most recent call last):",
            '  File "/opt/ACE-Step-1.5/acestep/inference.py", line 813, in generate_music',
            "torch.OutOfMemoryError: CUDA out of memory while rendering private song prompt",
            "2026-11-04 | ERROR    | acestep.api:run - failed " + "x" * 600,
            "[API Server] ERROR: Primary model failed to load",
        ])
        lines = server.log_excerpt(log, ("private song prompt",))
        self.assertEqual(len(lines), 5)
        self.assertTrue(all("private song prompt" not in line for line in lines))
        self.assertIn("[redacted]", lines[2])
        self.assertTrue(all(len(line) <= server.EXCERPT_WIDTH for line in lines))


if __name__ == "__main__":
    unittest.main()
