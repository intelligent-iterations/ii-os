"""Model folders: the manifest each runner ships, and the pre-run check that the
operator's read-only folder holds every file the requested profile needs."""

from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import unittest

from tests.support import RUNNERS, TempDir, load

models = load("scripts/ii_os_model_folder.py", "ii_os_model_folder")
publish = load("scripts/ii_os_publish.py", "ii_os_publish")

WEIGHTS = b"example weights " * 8
MANIFEST = {
    "schema_version": 1,
    "runner": "example-runner",
    "profiles": {
        "base": ["diffusion_models/base.safetensors", "vae/ae.safetensors"],
        "with-lora": ["diffusion_models/base.safetensors", "vae/ae.safetensors", "loras/style.safetensors"],
        "snapshot": ["text_encoders/encoder"],
    },
    "files": [
        {
            "path": "diffusion_models/base.safetensors",
            "size_bytes": len(WEIGHTS),
            "sha256": hashlib.sha256(WEIGHTS).hexdigest(),
            "source": "https://huggingface.co/example-org/example-model/blob/0123456789abcdef0123456789abcdef01234567/base.safetensors",
            "license": "Apache-2.0",
        },
        {
            "path": "vae/ae.safetensors",
            "size_bytes": None,
            "sha256": None,
            "source": "https://huggingface.co/example-org/example-model",
            "license": "Apache-2.0",
        },
        {
            "path": "loras/style.safetensors",
            "size_bytes": 4,
            "sha256": None,
            "source": "https://huggingface.co/example-org/example-lora",
            "license": "unstated",
            "optional": True,
            "note": "No license is stated upstream; the runner works without it.",
        },
        {
            "path": "text_encoders/encoder",
            "kind": "directory",
            "size_bytes": None,
            "sha256": None,
            "source": "https://huggingface.co/example-org/example-encoder",
            "license": "MIT",
        },
    ],
}


class ManifestTest(unittest.TestCase):
    def test_accepts_a_well_formed_manifest(self) -> None:
        manifest = models.Manifest.parse(MANIFEST)
        self.assertEqual(manifest.runner, "example-runner")
        self.assertEqual(sorted(manifest.profiles), ["base", "snapshot", "with-lora"])

    def test_rejects_paths_that_leave_the_runner_folder(self) -> None:
        for path in ("../other/model.safetensors", "/models/x.safetensors", "a/../../b", "a\\b", "", "a//b"):
            broken = copy.deepcopy(MANIFEST)
            broken["files"][0]["path"] = path
            broken["profiles"] = {"base": [path]}
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "relative path"):
                models.Manifest.parse(broken)

    def test_rejects_a_profile_naming_an_unlisted_file(self) -> None:
        broken = copy.deepcopy(MANIFEST)
        broken["profiles"]["base"].append("unet/missing.safetensors")
        with self.assertRaisesRegex(ValueError, "unet/missing.safetensors"):
            models.Manifest.parse(broken)

    def test_every_file_names_its_source_and_license(self) -> None:
        for field, value in (("source", "http://insecure.example.com/x"), ("license", ""), ("sha256", "abc")):
            broken = copy.deepcopy(MANIFEST)
            broken["files"][0][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, field):
                models.Manifest.parse(broken)


class SourceObjectManifestTest(unittest.TestCase):
    """Manifests may name a source as repository, revision and file name, and
    may omit profiles when a runner reads one fixed set of files."""

    MANIFEST = {
        "schema_version": 1,
        "runner": "example-coder",
        "files": [
            {
                "path": "sources/example.gguf",
                "size_bytes": 4,
                "sha256": "0" * 64,
                "source": {
                    "repository": "https://huggingface.co/example-org/example-gguf",
                    "revision": "0123456789abcdef0123456789abcdef01234567",
                    "filename": "example.gguf",
                },
                "license": "Apache-2.0",
            }
        ],
    }

    def test_a_repository_source_and_a_default_profile_are_accepted(self) -> None:
        manifest = models.Manifest.parse(self.MANIFEST)
        self.assertEqual(manifest.profiles, {"default": ["sources/example.gguf"]})
        self.assertEqual(
            manifest.files["sources/example.gguf"].source,
            "https://huggingface.co/example-org/example-gguf (revision 0123456789abcdef0123456789abcdef01234567, example.gguf)",
        )

    def test_a_repository_source_must_be_https_and_pinned(self) -> None:
        for source in (
            {"repository": "http://example.com/x", "revision": "0" * 40, "filename": "x"},
            {"repository": "https://example.com/x", "revision": "main", "filename": "x"},
            {"repository": "https://example.com/x", "revision": "0" * 40},
        ):
            broken = copy.deepcopy(self.MANIFEST)
            broken["files"][0]["source"] = source
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "source"):
                models.Manifest.parse(broken)


class FolderCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.root = self.temp.path / "models"
        self.folder = self.root / "example-runner"
        (self.folder / "diffusion_models").mkdir(parents=True)
        (self.folder / "vae").mkdir()
        (self.folder / "diffusion_models" / "base.safetensors").write_bytes(WEIGHTS)
        (self.folder / "vae" / "ae.safetensors").write_bytes(b"vae")
        self.manifest = models.Manifest.parse(MANIFEST)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_a_complete_folder_passes(self) -> None:
        report = models.check(self.root, self.manifest, "base")
        self.assertEqual(report.problems, [])
        self.assertEqual(report.folder, self.folder)

    def test_missing_files_are_all_named(self) -> None:
        (self.folder / "vae" / "ae.safetensors").unlink()
        (self.folder / "diffusion_models" / "base.safetensors").unlink()
        report = models.check(self.root, self.manifest, "base")
        self.assertEqual(len(report.problems), 2)
        self.assertIn("vae/ae.safetensors is missing", "\n".join(report.problems))

    def test_a_missing_optional_file_is_a_note_not_a_problem(self) -> None:
        report = models.check(self.root, self.manifest, "with-lora")
        self.assertEqual(report.problems, [])
        self.assertIn("loras/style.safetensors", "\n".join(report.notes))

    def test_a_size_mismatch_is_a_problem(self) -> None:
        (self.folder / "diffusion_models" / "base.safetensors").write_bytes(WEIGHTS[:-1])
        report = models.check(self.root, self.manifest, "base")
        self.assertIn("size", report.problems[0])

    def test_a_symlink_that_leaves_the_folder_will_not_resolve_in_the_container(self) -> None:
        outside = self.temp.path / "elsewhere.safetensors"
        outside.write_bytes(b"vae")
        (self.folder / "vae" / "ae.safetensors").unlink()
        os.symlink(outside, self.folder / "vae" / "ae.safetensors")
        report = models.check(self.root, self.manifest, "base")
        self.assertIn("outside", report.problems[0])

    def test_a_symlink_inside_the_folder_is_fine(self) -> None:
        shared = self.folder / "shared"
        shared.mkdir()
        (self.folder / "vae" / "ae.safetensors").rename(shared / "ae.safetensors")
        os.symlink(shared / "ae.safetensors", self.folder / "vae" / "ae.safetensors")
        self.assertEqual(models.check(self.root, self.manifest, "base").problems, [])

    def test_a_directory_entry_must_be_a_non_empty_folder(self) -> None:
        report = models.check(self.root, self.manifest, "snapshot")
        self.assertIn("text_encoders/encoder is missing", report.problems[0])
        encoder = self.folder / "text_encoders" / "encoder"
        encoder.mkdir(parents=True)
        self.assertIn("empty", models.check(self.root, self.manifest, "snapshot").problems[0])
        (encoder / "config.json").write_text("{}")
        self.assertEqual(models.check(self.root, self.manifest, "snapshot").problems, [])

    def test_a_missing_runner_folder_names_the_expected_path(self) -> None:
        report = models.check(self.temp.path / "empty-root", self.manifest, "base")
        self.assertIn("example-runner", report.problems[0])

    def test_an_unknown_profile_fails(self) -> None:
        with self.assertRaisesRegex(ValueError, "profile"):
            models.check(self.root, self.manifest, "turbo")

    def test_sha256_is_verified_only_when_asked(self) -> None:
        (self.folder / "diffusion_models" / "base.safetensors").write_bytes(b"x" * len(WEIGHTS))
        self.assertEqual(models.check(self.root, self.manifest, "base").problems, [])
        report = models.check(self.root, self.manifest, "base", verify_sha256=True)
        self.assertIn("sha256", report.problems[0])


class FailureCodeTest(unittest.TestCase):
    """A missing model reaches ii-os as the workflow's own code, not a generic failure."""

    CODE = "classification_model_missing"

    def setUp(self) -> None:
        self.temp = TempDir()
        self.root = self.temp.path / "models"
        (self.root / "example-runner" / "vae").mkdir(parents=True)
        (self.root / "example-runner" / "vae" / "ae.safetensors").write_bytes(b"vae")
        self.manifest = self.temp.path / "models.json"
        self.manifest.write_text(json.dumps(MANIFEST), encoding="utf-8")
        self.work = self.temp.path / "run"
        (self.work / "out").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def check(self, *extra: str) -> int:
        return models.main(
            ["check", "--manifest", str(self.manifest), "--model-root", str(self.root), "--profile", "base", *extra],
            env={},
        )

    def test_a_missing_model_writes_the_code_the_failure_report_reads(self) -> None:
        self.assertEqual(self.check("--work-dir", str(self.work), "--failure-code", self.CODE), 1)
        failure = self.work / "out" / "failure.json"
        self.assertEqual(json.loads(failure.read_text(encoding="utf-8")), {"errorCode": self.CODE})
        self.assertEqual(
            publish.failure_code(self.work, default="classification_workflow_failed", allowed=(self.CODE,)),
            self.CODE,
        )

    def test_a_complete_folder_writes_no_failure(self) -> None:
        (self.root / "example-runner" / "diffusion_models").mkdir()
        (self.root / "example-runner" / "diffusion_models" / "base.safetensors").write_bytes(WEIGHTS)
        self.assertEqual(self.check("--work-dir", str(self.work), "--failure-code", self.CODE), 0)
        self.assertFalse((self.work / "out" / "failure.json").exists())

    def test_without_a_failure_code_nothing_is_written(self) -> None:
        self.assertEqual(self.check(), 1)
        self.assertFalse((self.work / "out" / "failure.json").exists())

    def test_the_code_is_a_stable_identifier_and_needs_a_run_directory(self) -> None:
        with self.assertRaisesRegex(ValueError, "failure code"):
            self.check("--work-dir", str(self.work), "--failure-code", "model missing!")
        with self.assertRaisesRegex(ValueError, "--work-dir"):
            self.check("--failure-code", self.CODE)

    def test_a_symlinked_output_folder_is_not_followed(self) -> None:
        elsewhere = self.temp.path / "elsewhere"
        elsewhere.mkdir()
        (self.work / "out").rmdir()
        os.symlink(elsewhere, self.work / "out")
        with self.assertRaisesRegex(ValueError, "out"):
            self.check("--work-dir", str(self.work), "--failure-code", self.CODE)
        self.assertEqual(list(elsewhere.iterdir()), [])


class ShippedManifestsTest(unittest.TestCase):
    """Every runner the kit ships carries a manifest this checker accepts."""

    def test_every_runner_manifest_parses(self) -> None:
        manifests = sorted(RUNNERS.glob("*/models.json"))
        self.assertTrue(manifests, "the kit ships no runner manifests")
        for path in manifests:
            with self.subTest(runner=path.parent.name):
                manifest = models.Manifest.parse(json.loads(path.read_text(encoding="utf-8")))
                self.assertEqual(manifest.runner, path.parent.name)
                self.assertTrue(manifest.profiles)


if __name__ == "__main__":
    unittest.main()
