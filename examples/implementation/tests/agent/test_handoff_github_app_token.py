"""Operation-scoped GitHub App token minting by immutable repository ID."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
KIT = Path(__file__).resolve().parents[2]
SCRIPTS = KIT / "scripts" / "agent"
for _path in (SCRIPTS / "worker", SCRIPTS):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

import github_app_repository_token as TOKEN  # noqa: E402

SLUG = "example-app-bot"


class _Api:
    def __init__(self, *, minted=None, slug=SLUG):
        self.calls = []
        self.slug = slug
        self.minted = minted or {
            "token": "github-token-value-123456789",
            "expires_at": "2099-01-01T00:00:00Z",
            "permissions": {"contents": "write", "metadata": "read"},
            "repository_selection": "selected",
            "repositories": [{"id": 123, "full_name": "acme-co/example-app"}],
        }

    def request(self, method, path, authorization, body=None):
        self.calls.append((method, path, authorization, body))
        if path == "/app":
            return {"id": 77, "slug": self.slug}
        if path.endswith("/installation"):
            return {"id": 88, "app_id": 77, "app_slug": self.slug}
        if path.endswith("/access_tokens"):
            return self.minted
        raise AssertionError(f"unexpected GitHub path: {path}")


def _mint(api, **overrides):
    arguments = {
        "app_id": 77,
        "private_key": "test-key",
        "expected_app_slug": SLUG,
        "repository": "acme-co/example-app",
        "repository_id": 123,
        "permission": "contents",
        "level": "write",
        "api": api,
        "jwt_factory": lambda app_id, key: "signed-app-jwt",
    }
    arguments.update(overrides)
    return TOKEN.mint_repository_token(**arguments)


class GitHubAppRepositoryTokenTest(unittest.TestCase):
    def test_mints_only_the_exact_numeric_repository(self):
        api = _Api()
        result = _mint(api)
        self.assertEqual(result.repository_id, 123)
        self.assertEqual(result.app_slug, SLUG)
        self.assertEqual(
            api.calls[1][1], "/repos/acme-co/example-app/installation"
        )
        self.assertEqual(
            api.calls[2],
            (
                "POST",
                "/app/installations/88/access_tokens",
                "signed-app-jwt",
                {
                    "repository_ids": [123],
                    "permissions": {"contents": "write"},
                },
            ),
        )
        self.assertEqual(len(api.calls), 3)

    def test_accepts_display_name_for_exact_reported_target_id(self):
        api = _Api(minted={
            "token": "github-token-value-123456789",
            "expires_at": "2099-01-01T00:00:00Z",
            "permissions": {"contents": "write"},
            "repository_selection": "selected",
            "repositories": [{"id": 123, "full_name": "acme-co/renamed-app"}],
        })
        self.assertEqual(_mint(api).repository_id, 123)

    def test_rejects_another_app_identity(self):
        with self.assertRaisesRegex(RuntimeError, "identity does not match"):
            _mint(_Api(slug="other-app-bot"))
        with self.assertRaisesRegex(RuntimeError, "slug is invalid"):
            _mint(_Api(), expected_app_slug="")

    def test_rejects_substitution_and_overprivilege(self):
        base = {
            "token": "github-token-value-123456789",
            "expires_at": "2099-01-01T00:00:00Z",
            "permissions": {"contents": "write"},
            "repository_selection": "selected",
        }
        for minted in [
            {**base, "repositories": [
                {"id": 999, "full_name": "acme-co/example-app"},
            ]},
            {**base, "repositories": [
                {"id": 123, "full_name": "acme-co/example-app"},
                {"id": 999, "full_name": "acme-co/other-app"},
            ]},
            {**base, "permissions": {"contents": "write", "issues": "write"}},
            {**base, "repository_selection": "all"},
            {**base, "expires_at": "2000-01-01T00:00:00Z", "repositories": [
                {"id": 123, "full_name": "acme-co/example-app"},
            ]},
        ]:
            with self.subTest(minted=minted):
                with self.assertRaises(RuntimeError):
                    _mint(_Api(minted=minted))

    def test_rejects_unsupported_permission_requests(self):
        for overrides in (
            {"permission": "issues"},
            {"level": "admin"},
            {"repository": "not a repository"},
            {"repository_id": 0},
        ):
            with self.subTest(overrides=overrides):
                with self.assertRaises(RuntimeError):
                    _mint(_Api(), **overrides)

    def test_jwt_signing_uses_an_anonymous_key_handoff(self):
        if shutil.which("openssl") is None:
            self.skipTest("openssl is not installed")
        generated = subprocess.run(
            [
                "openssl", "genpkey", "-algorithm", "RSA",
                "-pkeyopt", "rsa_keygen_bits:2048",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=True,
            text=True,
        )
        jwt = TOKEN.github_app_jwt(77, generated.stdout)
        self.assertEqual(len(jwt.split(".")), 3)
        self.assertNotIn(generated.stdout.strip(), jwt)


class GitHubAppRepositoryTokenCommandTest(unittest.TestCase):
    def _environment(self, output):
        return {
            "II_OS_GITHUB_APP_ID": "77",
            "II_OS_GITHUB_APP_PRIVATE_KEY": "test-key",
            "II_OS_GITHUB_APP_SLUG": SLUG,
            "TARGET_REPOSITORY": "acme-co/example-app",
            "TARGET_REPOSITORY_ID": "123",
            "GITHUB_PERMISSION_LEVEL": "write",
            "GITHUB_OUTPUT": str(output),
        }

    def test_command_reads_operator_settings_and_writes_outputs(self):
        with tempfile.TemporaryDirectory() as value:
            output = Path(value) / "github-output"
            api = _Api()
            printed = []
            TOKEN.run(
                self._environment(output),
                api=api,
                jwt_factory=lambda app_id, key: "signed-app-jwt",
                emit=printed.append,
            )
            self.assertEqual(
                output.read_text(),
                "token=github-token-value-123456789\n"
                f"app-slug={SLUG}\n"
                "repository-id=123\n",
            )
            self.assertEqual(
                printed[0], "::add-mask::github-token-value-123456789"
            )
            summary = json.loads(printed[1])
            self.assertEqual(summary["app_slug"], SLUG)
            self.assertNotIn("github-token-value", printed[1])

    def test_command_fails_by_name_without_required_settings(self):
        for name in (
            "II_OS_GITHUB_APP_ID",
            "II_OS_GITHUB_APP_PRIVATE_KEY",
            "II_OS_GITHUB_APP_SLUG",
            "TARGET_REPOSITORY",
            "TARGET_REPOSITORY_ID",
            "GITHUB_PERMISSION_LEVEL",
            "GITHUB_OUTPUT",
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as value:
                environment = self._environment(Path(value) / "out")
                del environment[name]
                api = _Api()
                with self.assertRaisesRegex(SystemExit, name):
                    TOKEN.run(
                        environment,
                        api=api,
                        jwt_factory=lambda app_id, key: "signed-app-jwt",
                        emit=lambda line: None,
                    )
                self.assertEqual(api.calls, [])

    def test_script_reports_missing_slug_without_a_network_call(self):
        environment = {
            "PATH": os.environ.get("PATH", ""),
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        completed = subprocess.run(
            [sys.executable, str(SCRIPTS / "github_app_repository_token.py")],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("II_OS_GITHUB_APP_ID is required", completed.stderr)


if __name__ == "__main__":
    unittest.main()
