"""The container launch is where the isolation promises are kept, so the exact
docker arguments are asserted rather than assumed."""

from __future__ import annotations

from pathlib import Path
import unittest

from tests.support import TempDir, load

launcher = load("scripts/ii_os_run_container.py", "ii_os_run_container")

IMAGE = "registry.example.com/ii-os/comfyui-image@sha256:" + "a" * 64


class BuildCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.model_root = self.temp.path / "models"
        (self.model_root / "comfyui-image").mkdir(parents=True)
        self.work = self.temp.path / "ii-os-run-987654321-1"
        (self.work / "in").mkdir(parents=True)
        (self.work / "out").mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def build(self, **overrides: object) -> list[str]:
        options: dict[str, object] = {
            "image": IMAGE,
            "runner": "comfyui-image",
            "model_root": self.model_root,
            "work_dir": self.work,
            "name": "ii-os-comfyui-image-987654321-1",
            "gpu": True,
            "uid": 1001,
            "gid": 1001,
            "args": ["run"],
        }
        options.update(overrides)
        return launcher.build_command(**options)

    def test_the_container_has_no_network_and_no_privileges(self) -> None:
        command = self.build()
        self.assertEqual(command[:2], ["docker", "run"])
        joined = " ".join(command)
        self.assertIn("--network none", joined)
        self.assertIn("--cap-drop ALL", joined)
        self.assertIn("--security-opt no-new-privileges", joined)
        self.assertIn("--user 1001:1001", joined)
        self.assertIn("--pull never", joined)
        self.assertIn("--rm", command)
        self.assertNotIn("--privileged", command)
        self.assertNotIn("/var/run/docker.sock", joined)
        self.assertEqual(command[-2:], [IMAGE, "run"])

    def test_models_and_inputs_are_read_only_and_only_outputs_are_writable(self) -> None:
        mounts = [command for command in self.build() if command.startswith("type=bind")]
        folder = (self.model_root / "comfyui-image").resolve()
        self.assertEqual(
            mounts,
            [
                f"type=bind,source={folder},target=/models,readonly",
                f"type=bind,source={(self.work / 'in').resolve()},target=/work/in,readonly",
                f"type=bind,source={(self.work / 'out').resolve()},target=/work/out",
            ],
        )

    def test_model_libraries_are_told_they_are_offline(self) -> None:
        joined = " ".join(self.build())
        for setting in ("HF_HUB_OFFLINE=1", "TRANSFORMERS_OFFLINE=1", "HOME=/tmp/home", "USER=ii-os-runner"):
            self.assertIn(setting, joined)

    def test_gpu_is_requested_only_for_gpu_runners(self) -> None:
        self.assertIn("--gpus", self.build())
        self.assertNotIn("--gpus", self.build(gpu=False))

    def test_the_image_must_be_digest_pinned(self) -> None:
        for image in ("example/comfyui-image:latest", "example/comfyui-image", IMAGE.replace("a" * 64, "a" * 63)):
            with self.subTest(image=image), self.assertRaisesRegex(ValueError, "digest"):
                self.build(image=image)

    def test_the_runner_model_folder_must_exist(self) -> None:
        with self.assertRaisesRegex(ValueError, "seedvr2-video"):
            self.build(runner="seedvr2-video")

    def test_a_runner_that_needs_no_models_mounts_none(self) -> None:
        command = self.build(runner="media-render", model_root=None, gpu=False)
        self.assertFalse(any("target=/models" in item for item in command))

    def test_paths_that_would_break_mount_syntax_are_refused(self) -> None:
        odd = self.temp.path / "odd,dir"
        (odd / "in").mkdir(parents=True)
        (odd / "out").mkdir()
        with self.assertRaisesRegex(ValueError, "comma"):
            self.build(work_dir=odd)

    def test_the_run_name_is_derived_from_the_run(self) -> None:
        self.assertEqual(
            launcher.container_name("comfyui-image", run_id=987654321, run_attempt=2),
            "ii-os-comfyui-image-987654321-2",
        )

    def test_extra_environment_is_limited_to_runner_settings(self) -> None:
        command = self.build(extra_env={"II_OS_OPTION_STEPS": "8"})
        self.assertIn("II_OS_OPTION_STEPS=8", command)
        with self.assertRaisesRegex(ValueError, "environment"):
            self.build(extra_env={"II_OS_TOKEN": "x"})
        with self.assertRaisesRegex(ValueError, "environment"):
            self.build(extra_env={"PATH": "/tmp"})


if __name__ == "__main__":
    unittest.main()
