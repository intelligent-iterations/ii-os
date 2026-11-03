import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from mobile_engine_host_tools import prepare_host_build_tools


class MobileEngineHostToolsTest(unittest.TestCase):
    def test_locked_python_host_tool_has_reproducible_launcher(self):
        lock = json.loads(
            Path(__file__).with_name("mobile_engine_lock.json").read_text()
        )
        meson = next(
            tool for tool in lock["host_build_tools"] if tool["name"] == "meson"
        )
        with tempfile.TemporaryDirectory(prefix="ii-mobile-meson-test-") as owned:
            workspace = Path(owned)
            source = workspace / "host-tools/meson-unpacked/meson-1.11.2"

            def download_fixture(url, sha256, destination):
                self.assertEqual(url, meson["url"])
                self.assertEqual(sha256, meson["sha256"])
                destination.write_bytes(b"locked-meson-archive")

            def extract_fixture(archive, destination):
                self.assertTrue(archive.is_file())
                source.mkdir(parents=True)
                (source / "COPYING").write_text("Apache-2.0\n", encoding="utf-8")
                (source / "meson.py").write_text(
                    "import sys\n"
                    "if sys.argv[1:] == ['--version']:\n"
                    "    print('1.11.2')\n"
                    "else:\n"
                    "    raise SystemExit(2)\n",
                    encoding="utf-8",
                )

            def source_record_fixture(
                name, repository, revision, path, declared_license_paths
            ):
                self.assertEqual(path, source)
                self.assertEqual(declared_license_paths, ["COPYING"])
                return {"name": name, "repository": repository, "revision": revision}

            previous_path = os.environ.get("PATH")
            try:
                identities, sources = prepare_host_build_tools(
                    workspace,
                    {"host_build_tools": [meson]},
                    "ios",
                    download=download_fixture,
                    extract=extract_fixture,
                    record_source=source_record_fixture,
                )
            finally:
                if previous_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = previous_path

            executable = workspace / "host-tools/meson-prefix/bin/meson"
            self.assertEqual(identities[0]["name"], "meson")
            self.assertEqual(identities[0]["version"], "1.11.2")
            self.assertEqual(identities[0]["interpreter"], "/usr/bin/python3")
            self.assertRegex(identities[0]["interpreter_sha256"], r"^[0-9a-f]{64}$")
            self.assertEqual(sources[0]["name"], "meson")
            self.assertNotIn(owned, executable.read_text(encoding="utf-8"))
            result = subprocess.run(
                [str(executable), "--version"],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stdout.strip(), "1.11.2")


if __name__ == "__main__":
    unittest.main()
