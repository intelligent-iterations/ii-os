from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import attest_apple_build_tools as apple_tools


class AppleBuildToolAttestationTest(unittest.TestCase):
    def test_path_alias_may_select_the_same_attested_executable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-apple-path-test-") as owned:
            root = Path(owned)
            executable = root / "system-volume/xcrun"
            executable.parent.mkdir()
            executable.write_bytes(b"xcrun")
            alias = root / "usr-bin-xcrun"
            alias.symlink_to(executable)

            self.assertTrue(
                apple_tools._selects_attested_executable(str(alias), executable)
            )
            self.assertTrue(
                apple_tools._selects_attested_executable(str(executable), alias)
            )

    def test_path_selection_rejects_missing_or_different_executable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-apple-path-test-") as owned:
            root = Path(owned)
            expected = root / "expected"
            expected.write_bytes(b"expected")
            different = root / "different"
            different.write_bytes(b"different")
            dangling = root / "dangling"
            dangling.symlink_to("missing")

            self.assertFalse(
                apple_tools._selects_attested_executable(None, expected)
            )
            self.assertFalse(
                apple_tools._selects_attested_executable(str(different), expected)
            )
            self.assertFalse(
                apple_tools._selects_attested_executable(str(dangling), expected)
            )

    def test_clean_checkout_rejects_any_untracked_or_modified_byte(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="ii-apple-tool-checkout-test-"
        ) as owned:
            root = Path(owned) / "homebrew-core"
            root.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "dev"], cwd=root, check=True)
            subprocess.run(
                ["git", "config", "user.name", "ii-test"], cwd=root, check=True
            )
            subprocess.run(
                ["git", "config", "user.email", "ii-test@example.invalid"],
                cwd=root,
                check=True,
            )
            formula = root / "Formula/a/autoconf.rb"
            formula.parent.mkdir(parents=True)
            formula.write_text("class Autoconf; end\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(
                ["git", "commit", "-q", "-m", "fixture"], cwd=root, check=True
            )
            repository = "https://github.com/Homebrew/homebrew-core.git"
            subprocess.run(
                ["git", "remote", "add", "origin", repository],
                cwd=root,
                check=True,
            )
            revision = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            subprocess.run(
                [
                    "git",
                    "config",
                    "url.https://credential.invalid@github.com/.insteadOf",
                    "https://github.com/",
                ],
                cwd=root,
                check=True,
            )
            effective_remote = subprocess.run(
                ["git", "remote", "get-url", "origin"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            self.assertNotEqual(effective_remote, repository)
            with self.assertRaisesRegex(
                apple_tools.AttestationError, "does not match its lock"
            ):
                apple_tools._verify_clean_checkout(root, revision, repository)
            subprocess.run(
                [
                    "git",
                    "config",
                    "--unset-all",
                    "url.https://credential.invalid@github.com/.insteadOf",
                ],
                cwd=root,
                check=True,
            )

            injected = {
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": (
                    "url.https://credential.invalid@github.com/.insteadOf"
                ),
                "GIT_CONFIG_VALUE_0": "https://github.com/",
            }
            previous = {key: os.environ.get(key) for key in injected}
            os.environ.update(injected)
            try:
                effective_remote = subprocess.run(
                    ["git", "remote", "get-url", "origin"],
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.strip()
                self.assertNotEqual(effective_remote, repository)
                self.assertEqual(
                    apple_tools._verify_clean_checkout(root, revision, repository),
                    revision,
                )
            finally:
                for key, value in previous.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value

            (root / ".ii-disposable-owner").write_text(
                "must make checkout dirty\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(apple_tools.AttestationError, "dirty"):
                apple_tools._verify_clean_checkout(root, revision, repository)

    def test_installed_tree_digest_covers_files_links_and_modes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-apple-tool-tree-test-") as owned:
            root = Path(owned) / "formula-prefix"
            binary = root / "bin/tool"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"tool-v1")
            binary.chmod(0o755)
            (root / "tool-link").symlink_to("bin/tool")

            first = apple_tools._tree_attestation(root)
            self.assertEqual(first["file_count"], 1)
            self.assertEqual(first["link_count"], 1)
            self.assertEqual(first["total_bytes"], len(b"tool-v1"))

            binary.write_bytes(b"tool-v2")
            binary.chmod(0o700)
            second = apple_tools._tree_attestation(root)
            self.assertNotEqual(first["sha256"], second["sha256"])

            os.unlink(root / "tool-link")
            (root / "tool-link").symlink_to("bin/missing")
            third = apple_tools._tree_attestation(root)
            self.assertNotEqual(second["sha256"], third["sha256"])

    def test_installed_tree_rejects_links_outside_the_attested_root(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-apple-tool-link-test-") as owned:
            root = Path(owned) / "formula-prefix"
            root.mkdir()
            (root / "escape").symlink_to("../outside")
            with self.assertRaisesRegex(
                apple_tools.AttestationError, "escapes its root"
            ):
                apple_tools._tree_attestation(root)

    def test_file_digest_rejects_a_link_even_when_its_target_is_regular(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-apple-tool-file-test-") as owned:
            root = Path(owned)
            target = root / "tool"
            target.write_bytes(b"attested tool")
            linked = root / "tool-link"
            linked.symlink_to(target.name)
            with self.assertRaisesRegex(
                apple_tools.AttestationError, "cannot be hashed safely"
            ):
                apple_tools._sha256(linked)

    def test_formula_hash_rejects_an_intermediate_directory_link(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-apple-formula-link-test-") as owned:
            root = Path(owned) / "homebrew-core"
            outside = Path(owned) / "outside"
            root.mkdir()
            (outside / "a").mkdir(parents=True)
            (outside / "a/autoconf.rb").write_bytes(b"formula")
            (root / "Formula").symlink_to(outside, target_is_directory=True)
            pinned = apple_tools.PinnedDirectory(root)
            try:
                with self.assertRaisesRegex(
                    apple_tools.TreeAttestationError,
                    "directory is unsafe",
                ):
                    pinned.hash_file("Formula/a/autoconf.rb", 1024)
            finally:
                pinned.close()


if __name__ == "__main__":
    unittest.main()
