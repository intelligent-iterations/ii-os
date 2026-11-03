from __future__ import annotations

import hashlib
import http.client
import io
import json
import os
import tarfile
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import build_web_engine
from verify_web_engine import _memories
from web_engine_common import WebEngineError, download_exact, extract_exact


class _DownloadResponse:
    def __init__(
        self,
        chunks: list[bytes | BaseException],
        *,
        content_length: int | None = None,
        final_url: str = "https://example.invalid/source.tar",
    ) -> None:
        self.chunks = list(chunks)
        self.final_url = final_url
        self.headers = (
            {} if content_length is None else {"Content-Length": str(content_length)}
        )

    def __enter__(self):
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def geturl(self) -> str:
        return self.final_url

    def read(self, size: int) -> bytes:
        value = self.chunks.pop(0)
        if isinstance(value, BaseException):
            raise value
        return value


class WebEngineRecipeTest(unittest.TestCase):
    def test_zlib_uses_the_single_archive_configure_path(self) -> None:
        source = Path("/owned/sources/zlib")
        prefix = Path("/owned/toolchain/prefix")
        environment = {"CC": "emcc"}
        with (
            mock.patch.object(build_web_engine, "run") as run,
            mock.patch.object(build_web_engine, "_make") as make,
        ):
            build_web_engine._configure_zlib(
                source, prefix, environment, "4"
            )

        run.assert_called_once_with(
            [
                "emconfigure",
                "./configure",
                "--static",
                f"--prefix={prefix}",
            ],
            source,
            environment,
        )
        make.assert_called_once_with(source, environment, "4")

    def test_partial_stream_is_removed_and_retried(self) -> None:
        payload = b"reviewed-source"
        responses = [
            _DownloadResponse(
                [b"partial", http.client.IncompleteRead(b"", 10)]
            ),
            _DownloadResponse([payload, b""]),
        ]
        with tempfile.TemporaryDirectory(prefix="ii-web-download-test-") as owned:
            destination = Path(owned) / "source.tar"
            with (
                mock.patch(
                    "web_engine_common.urllib.request.urlopen",
                    side_effect=responses,
                ) as opened,
                mock.patch("web_engine_common.time.sleep"),
            ):
                download_exact(
                    "https://example.invalid/source.tar",
                    hashlib.sha256(payload).hexdigest(),
                    destination,
                )
            self.assertEqual(opened.call_count, 2)
            self.assertEqual(destination.read_bytes(), payload)
            self.assertFalse(destination.with_suffix(".tar.partial").exists())

    def test_clean_early_eof_and_checksum_mismatch_are_retried(self) -> None:
        payload = b"complete-reviewed-source"
        responses = [
            _DownloadResponse([b"partial", b""]),
            _DownloadResponse(
                [payload, b""],
                content_length=len(payload),
            ),
        ]
        with tempfile.TemporaryDirectory(prefix="ii-web-eof-test-") as owned:
            destination = Path(owned) / "source.tar"
            with (
                mock.patch(
                    "web_engine_common.urllib.request.urlopen",
                    side_effect=responses,
                ) as opened,
                mock.patch("web_engine_common.time.sleep"),
            ):
                download_exact(
                    "https://example.invalid/source.tar",
                    hashlib.sha256(payload).hexdigest(),
                    destination,
                )
            self.assertEqual(opened.call_count, 2)
            self.assertEqual(destination.read_bytes(), payload)

    def test_exact_download_fails_over_to_a_reviewed_https_location(self) -> None:
        payload = b"complete-reviewed-source"
        responses = [
            urllib.error.URLError("primary unavailable"),
            urllib.error.URLError("primary unavailable"),
            urllib.error.URLError("primary unavailable"),
            urllib.error.URLError("primary unavailable"),
            urllib.error.URLError("primary unavailable"),
            _DownloadResponse([payload, b""]),
        ]
        with tempfile.TemporaryDirectory(prefix="ii-web-failover-test-") as owned:
            destination = Path(owned) / "source.tar"
            with (
                mock.patch(
                    "web_engine_common.urllib.request.urlopen",
                    side_effect=responses,
                ) as opened,
                mock.patch("web_engine_common.time.sleep") as sleep,
            ):
                selected = download_exact(
                    "https://primary.example.invalid/source.tar",
                    hashlib.sha256(payload).hexdigest(),
                    destination,
                    fallback_urls=(
                        "https://fallback.example.invalid/source.tar",
                    ),
                )
            self.assertEqual(selected, "https://fallback.example.invalid/source.tar")
            self.assertEqual(opened.call_count, 6)
            self.assertEqual(
                opened.call_args_list[-1].args[0].full_url,
                "https://fallback.example.invalid/source.tar",
            )
            self.assertEqual(
                [call.args for call in sleep.call_args_list],
                [(2,), (4,), (6,), (8,)],
            )
            self.assertEqual(destination.read_bytes(), payload)

    def test_https_downgrade_rejects_location_and_uses_next_fallback(self) -> None:
        payload = b"complete-reviewed-source"
        responses = [
            _DownloadResponse(
                [payload, b""],
                final_url="http://primary.example.invalid/source.tar",
            ),
            _DownloadResponse([payload, b""]),
        ]
        with tempfile.TemporaryDirectory(
            prefix="ii-web-downgrade-test-",
        ) as owned:
            destination = Path(owned) / "source.tar"
            with (
                mock.patch(
                    "web_engine_common.urllib.request.urlopen",
                    side_effect=responses,
                ) as opened,
                mock.patch("web_engine_common.time.sleep") as sleep,
            ):
                selected = download_exact(
                    "https://primary.example.invalid/source.tar",
                    hashlib.sha256(payload).hexdigest(),
                    destination,
                    fallback_urls=(
                        "https://fallback.example.invalid/source.tar",
                    ),
                )
            self.assertEqual(
                selected,
                "https://fallback.example.invalid/source.tar",
            )
            self.assertEqual(opened.call_count, 2)
            sleep.assert_not_called()
            self.assertEqual(destination.read_bytes(), payload)

    def test_release_inputs_and_profile_are_exact_and_local_only(self) -> None:
        lock = json.loads(Path(__file__).with_name("web_engine_lock.json").read_text())
        self.assertEqual(lock["engine_version"], "n5.1.10")
        self.assertRegex(lock["toolchain"]["revision"], r"^[0-9a-f]{40}$")
        hashes = []
        for source in lock["sources"]:
            self.assertTrue(source["url"].startswith("https://"))
            for fallback_url in source.get("fallback_urls", []):
                self.assertTrue(fallback_url.startswith("https://"))
                self.assertNotEqual(fallback_url, source["url"])
            self.assertRegex(source["sha256"], r"^[0-9a-f]{64}$")
            hashes.append(source["sha256"])
        self.assertEqual(len(hashes), len(set(hashes)))
        profile = lock["release_profile"]
        self.assertIn("--disable-network", profile["required_flags"])
        self.assertIn("--disable-pthreads", profile["required_flags"])
        self.assertIn("--enable-gpl", profile["forbidden_flags"])
        self.assertEqual(profile["maximum_memory_bytes"], 512 * 1024 * 1024)

    def test_archive_links_are_rejected_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-web-archive-test-") as owned:
            root = Path(owned)
            archive = root / "source.tar"
            with tarfile.open(archive, "w") as output:
                directory = tarfile.TarInfo("source")
                directory.type = tarfile.DIRTYPE
                output.addfile(directory)
                link = tarfile.TarInfo("source/escape")
                link.type = tarfile.SYMTYPE
                link.linkname = "../../escape"
                output.addfile(link)
            with self.assertRaisesRegex(WebEngineError, "link/device"):
                extract_exact(archive, root / "output")

    def test_archive_source_timestamps_survive_safe_extraction(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-web-mtime-test-") as owned:
            root = Path(owned)
            archive = root / "source.tar"
            with tarfile.open(archive, "w") as output:
                for name, mtime in (("Makefile.in", 200), ("Makefile.am", 100)):
                    payload = name.encode()
                    member = tarfile.TarInfo(f"source/{name}")
                    member.size = len(payload)
                    member.mtime = mtime
                    output.addfile(member, io.BytesIO(payload))
            destination = root / "output"
            extract_exact(archive, destination)
            generated = destination / "source/Makefile.in"
            source = destination / "source/Makefile.am"
            self.assertEqual(os.stat(generated).st_mtime, 200)
            self.assertEqual(os.stat(source).st_mtime, 100)
            self.assertGreater(generated.stat().st_mtime, source.stat().st_mtime)

    def test_wasm_memory_parser_requires_an_explicit_unshared_maximum(self) -> None:
        header = b"\x00asm\x01\x00\x00\x00"
        bounded_memory = b"\x05\x06\x01\x01\x80\x04\x80\x40"
        self.assertEqual(
            _memories(header + bounded_memory),
            [{
                "minimum_pages": 512,
                "maximum_pages": 8192,
                "shared": False,
                "memory64": False,
            }],
        )
        shared_memory = b"\x05\x06\x01\x03\x80\x04\x80\x40"
        self.assertTrue(_memories(header + shared_memory)[0]["shared"])

    def test_emsdk_activation_uses_a_fixed_argv_helper(self) -> None:
        common = Path(__file__).with_name("web_engine_common.py").read_text()
        helper = Path(__file__).with_name("print_emsdk_environment.sh")
        self.assertTrue(helper.is_file())
        self.assertNotIn('"bash",\n        "-c"', common)
        self.assertIn('command = [str(helper), str(emsdk / "emsdk_env.sh")]', common)


if __name__ == "__main__":
    unittest.main()
