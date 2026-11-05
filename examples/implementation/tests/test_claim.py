"""The claim half of the generation contract: identity, response parsing,
source staging, and ownership-checked cleanup."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import unittest
from unittest import mock
import urllib.request
import urllib.response

from tests.support import FakeResponse, RecordingOpener, TempDir, json_body, load

connector = load("scripts/ii_os_connector.py", "ii_os_connector")
claim = load("scripts/ii_os_claim.py", "ii_os_claim")

ENV = {
    "II_OS_CONNECTOR_URL": "https://ii-os.example.com/api",
    "II_OS_TOKEN": "example-token",
    "II_REQUEST_ID": "req_0123456789abcdef",
    "GITHUB_REPOSITORY": "acme-co/example-app",
    "GITHUB_REPOSITORY_ID": "4242",
    "GITHUB_WORKFLOW_REF": "acme-co/example-app/.github/workflows/z-image-turbo-text-to-image.yml@refs/heads/main",
    "GITHUB_SHA": "0123456789abcdef0123456789abcdef01234567",
    "GITHUB_RUN_ID": "987654321",
    "GITHUB_RUN_ATTEMPT": "1",
}
UPLOAD = {
    "provider": "gcp_wif",
    "bucket": "example-app-assets",
    "objectPrefix": "workspaces/ws-example/ghost/req_0123456789abcdef/",
    "workloadIdentityProvider": "projects/123456/locations/global/workloadIdentityPools/example-pool/providers/example-provider",
    "serviceAccount": "uploader@example-project.iam.gserviceaccount.com",
}
ASSET_ID = "33449737-9e39-4d53-8040-f39d5f7bc3ce"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24


def future(minutes: int = 15) -> str:
    return (datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z")


def source(**overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "assetId": ASSET_ID,
        "url": "https://storage.googleapis.com/example-app-assets/source.png?X-Goog-Signature=abc",
        "expiresAt": future(),
        "contentType": "image/png",
        "sizeBytes": len(PNG),
    }
    value.update(overrides)
    return value


def response(inputs: dict[str, object] | None = None, **extra: object) -> dict[str, object]:
    data: dict[str, object] = {
        "requestId": ENV["II_REQUEST_ID"],
        "inputs": {"prompt": "a lighthouse at dusk", "aspect_ratio": "1:1"} if inputs is None else inputs,
        "gcpUpload": dict(UPLOAD),
    }
    data.update(extra)
    return {"data": data}


class RunIdentityTest(unittest.TestCase):
    def test_reads_the_run_from_the_github_environment(self) -> None:
        identity = connector.RunIdentity.from_env(ENV)
        self.assertEqual(identity.request_id, "req_0123456789abcdef")
        self.assertEqual(identity.repository_id, 4242)
        self.assertEqual(identity.run_id, 987654321)
        self.assertEqual(identity.run_attempt, 1)
        self.assertEqual(
            identity.claim_body(),
            {
                "requestId": "req_0123456789abcdef",
                "repository": "acme-co/example-app",
                "repositoryId": 4242,
                "workflowRef": ENV["GITHUB_WORKFLOW_REF"],
                "commitSha": ENV["GITHUB_SHA"],
                "runId": 987654321,
                "runAttempt": 1,
            },
        )

    def test_rejects_a_request_id_ii_os_would_not_issue(self) -> None:
        for bad in ("", "short", "has space in it", "a" * 65, "../../etc/passwd"):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "request id"):
                connector.RunIdentity.from_env({**ENV, "II_REQUEST_ID": bad})

    def test_rejects_a_non_numeric_run(self) -> None:
        with self.assertRaisesRegex(ValueError, "GITHUB_RUN_ID"):
            connector.RunIdentity.from_env({**ENV, "GITHUB_RUN_ID": "12x"})


class ConnectorTest(unittest.TestCase):
    def test_credential_bearing_requests_never_follow_redirects(self) -> None:
        for status in (301, 302, 303, 307, 308):
            requests = []

            def https_open(_handler, request):
                requests.append(request)
                if len(requests) == 1:
                    result = urllib.response.addinfourl(
                        io.BytesIO(b""), {"location": "https://other.example.com/collect"},
                        request.full_url, status,
                    )
                    result.msg = "Redirect"
                    return result
                result = urllib.response.addinfourl(
                    io.BytesIO(b'{"data":{}}'), {}, request.full_url, 200,
                )
                result.msg = "OK"
                return result

            with self.subTest(status=status), \
                    mock.patch.object(urllib.request, "_opener", None), \
                    mock.patch.object(urllib.request.HTTPSHandler, "https_open", https_open):
                client = connector.Connector(ENV["II_OS_CONNECTOR_URL"], "example-token")
                with self.assertRaises(connector.ConnectorError) as caught:
                    client.claim(connector.RunIdentity.from_env(ENV))
                self.assertEqual(caught.exception.status, status)
                self.assertEqual(len(requests), 1)
                self.assertEqual(requests[0].get_header("Authorization"), "Bearer example-token")

    def test_claim_posts_the_run_identity_with_the_bearer_token(self) -> None:
        opener = RecordingOpener([FakeResponse(200, response())])
        client = connector.Connector(ENV["II_OS_CONNECTOR_URL"], "example-token", opener=opener)
        data = client.claim(connector.RunIdentity.from_env(ENV))
        self.assertEqual(data["gcpUpload"]["bucket"], "example-app-assets")
        request = opener.requests[0]
        self.assertEqual(request["method"], "POST")
        self.assertEqual(request["url"], "https://ii-os.example.com/api?route=v1/workflow-runs/claim")
        self.assertEqual(request["headers"]["authorization"], "Bearer example-token")
        self.assertEqual(json_body(request)["runId"], 987654321)

    def test_a_rejected_claim_names_the_server_error_code(self) -> None:
        body = {"error": {"code": "workflow_token_scope_mismatch", "message": "The workflow credential is not scoped to this run."}}
        opener = RecordingOpener([FakeResponse(403, body)])
        client = connector.Connector(ENV["II_OS_CONNECTOR_URL"], "example-token", opener=opener)
        with self.assertRaises(connector.ConnectorError) as caught:
            client.claim(connector.RunIdentity.from_env(ENV))
        self.assertEqual(caught.exception.status, 403)
        self.assertEqual(caught.exception.code, "workflow_token_scope_mismatch")
        self.assertNotIn("example-token", str(caught.exception))

    def test_complete_reports_status_and_artifacts(self) -> None:
        opener = RecordingOpener([FakeResponse(200, {"data": {"status": "failed"}})])
        client = connector.Connector(ENV["II_OS_CONNECTOR_URL"], "example-token", opener=opener)
        client.complete(connector.RunIdentity.from_env(ENV), status="failed", error_code="image_generation_failed")
        request = opener.requests[0]
        self.assertEqual(
            request["url"],
            "https://ii-os.example.com/api?route=v1/workflow-runs/req_0123456789abcdef/complete",
        )
        self.assertEqual(
            json_body(request),
            {"runId": 987654321, "runAttempt": 1, "status": "failed", "errorCode": "image_generation_failed", "artifacts": []},
        )

    def test_the_connector_must_be_https_without_a_query(self) -> None:
        for bad in ("http://ii-os.example.com/api", "https://ii-os.example.com/api?route=x", "ii-os.example.com", ""):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "II_OS_CONNECTOR_URL"):
                connector.Connector(bad, "example-token")

    def test_complete_refuses_an_unknown_status(self) -> None:
        client = connector.Connector(ENV["II_OS_CONNECTOR_URL"], "example-token", opener=RecordingOpener([]))
        with self.assertRaisesRegex(ValueError, "status"):
            client.complete(connector.RunIdentity.from_env(ENV), status="done")


class ParseClaimTest(unittest.TestCase):
    def test_parses_inputs_and_the_upload_contract(self) -> None:
        parsed = claim.parse_claim(response()["data"], max_sources=0)
        self.assertEqual(parsed.inputs["prompt"], "a lighthouse at dusk")
        self.assertEqual(parsed.upload.provider, "gcp_wif")
        self.assertEqual(parsed.upload.object_prefix, UPLOAD["objectPrefix"])
        self.assertEqual(parsed.sources, [])

    def test_inputs_must_be_a_non_empty_string_map(self) -> None:
        for inputs in ({}, {"seed": 4}, {"prompt": None}):
            with self.subTest(inputs=inputs), self.assertRaisesRegex(ValueError, "inputs"):
                claim.parse_claim(response(inputs)["data"], max_sources=0)

    def test_an_upload_provider_this_kit_cannot_drive_fails_by_name(self) -> None:
        data = response()["data"]
        data["gcpUpload"] = {**UPLOAD, "provider": "example_s3"}
        with self.assertRaisesRegex(ValueError, "upload provider example_s3 is not supported"):
            claim.parse_claim(data, max_sources=0)

    def test_the_object_prefix_must_be_a_workspace_run_prefix(self) -> None:
        for prefix in ("other/ws/run/", "workspaces/ws/ghost/req", "workspaces/../x/", "/workspaces/ws/runs/r/"):
            data = response()["data"]
            data["gcpUpload"] = {**UPLOAD, "objectPrefix": prefix}
            with self.subTest(prefix=prefix), self.assertRaisesRegex(ValueError, "object prefix"):
                claim.parse_claim(data, max_sources=0)

    def test_source_assets_are_read_in_ordinal_order(self) -> None:
        second = source(assetId="e4a443e5-ef0d-4f23-b977-2d89959a0812")
        data = response(sourceAsset=source(), sourceAssets=[source(), second])["data"]
        parsed = claim.parse_claim(data, max_sources=3, source_kinds={"image"})
        self.assertEqual([item.asset_id for item in parsed.sources], [ASSET_ID, second["assetId"]])
        self.assertEqual([item.ordinal for item in parsed.sources], [0, 1])

    def test_a_legacy_single_source_is_accepted(self) -> None:
        parsed = claim.parse_claim(response(sourceAsset=source())["data"], max_sources=1, source_kinds={"image"})
        self.assertEqual(len(parsed.sources), 1)

    def test_more_sources_than_the_workflow_reads_fail(self) -> None:
        data = response(sourceAssets=[source(), source(assetId="e4a443e5-ef0d-4f23-b977-2d89959a0812")])["data"]
        with self.assertRaisesRegex(ValueError, "at most 1 source"):
            claim.parse_claim(data, max_sources=1, source_kinds={"image"})

    def test_a_source_of_the_wrong_kind_fails(self) -> None:
        data = response(sourceAssets=[source(contentType="video/mp4")])["data"]
        with self.assertRaisesRegex(ValueError, "video/mp4"):
            claim.parse_claim(data, max_sources=1, source_kinds={"image"})

    def test_a_source_url_must_be_signed_gcs_https(self) -> None:
        for url in (
            "http://storage.googleapis.com/b/o",
            "https://storage.googleapis.com.example.com/b/o",
            "https://example.com/b/o",
            "file:///etc/passwd",
        ):
            data = response(sourceAssets=[source(url=url)])["data"]
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, "Google Cloud Storage"):
                claim.parse_claim(data, max_sources=1, source_kinds={"image"})

    def test_an_expired_source_fails(self) -> None:
        data = response(sourceAssets=[source(expiresAt=future(-1))])["data"]
        with self.assertRaisesRegex(ValueError, "expired"):
            claim.parse_claim(data, max_sources=1, source_kinds={"image"})

    def test_error_messages_never_carry_the_signed_url(self) -> None:
        data = response(sourceAssets=[source(url="https://example.com/secret-signature")])["data"]
        with self.assertRaises(ValueError) as caught:
            claim.parse_claim(data, max_sources=1, source_kinds={"image"})
        self.assertNotIn("secret-signature", str(caught.exception))


class WorkDirectoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.identity = connector.RunIdentity.from_env(ENV)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_materialize_writes_private_inputs_and_staged_sources(self) -> None:
        parsed = claim.parse_claim(response(sourceAssets=[source()])["data"], max_sources=1, source_kinds={"image"})
        opener = RecordingOpener([FakeResponse(200, PNG)])
        work = claim.create_work_dir(self.temp.path, self.identity)
        claim.materialize(parsed, work, opener=opener)

        self.assertEqual(stat.S_IMODE(work.stat().st_mode), 0o700)
        inputs = json.loads((work / "in" / "inputs.json").read_text())
        self.assertEqual(inputs["aspect_ratio"], "1:1")
        sources = json.loads((work / "in" / "sources.json").read_text())
        self.assertEqual(
            sources,
            [
                {
                    "assetId": ASSET_ID,
                    "contentType": "image/png",
                    "file": "sources/00.png",
                    "kind": "image",
                    "ordinal": 0,
                    "role": None,
                    "sha256": hashlib.sha256(PNG).hexdigest(),
                    "sizeBytes": len(PNG),
                }
            ],
        )
        self.assertEqual((work / "in" / "sources" / "00.png").read_bytes(), PNG)
        self.assertTrue((work / "out").is_dir())
        self.assertNotIn("X-Goog-Signature", (work / "in" / "sources.json").read_text())

    def test_a_download_of_the_wrong_size_fails_and_keeps_nothing(self) -> None:
        parsed = claim.parse_claim(response(sourceAssets=[source()])["data"], max_sources=1, source_kinds={"image"})
        work = claim.create_work_dir(self.temp.path, self.identity)
        with self.assertRaisesRegex(ValueError, "size"):
            claim.materialize(parsed, work, opener=RecordingOpener([FakeResponse(200, PNG + b"extra")]))
        self.assertFalse((work / "in" / "sources" / "00.png").exists())

    def test_cleanup_removes_only_the_directory_this_run_owns(self) -> None:
        work = claim.create_work_dir(self.temp.path, self.identity)
        (work / "out" / "image.png").write_bytes(PNG)
        self.assertTrue(claim.cleanup(self.temp.path, self.identity))
        self.assertFalse(work.exists())
        self.assertFalse(claim.cleanup(self.temp.path, self.identity))

    def test_cleanup_refuses_a_directory_owned_by_another_run(self) -> None:
        work = claim.create_work_dir(self.temp.path, self.identity)
        other = connector.RunIdentity.from_env({**ENV, "II_REQUEST_ID": "req_another_request"})
        with self.assertRaisesRegex(ValueError, "does not match"):
            claim.cleanup(self.temp.path, other)
        self.assertTrue(work.exists())

    def test_cleanup_refuses_a_symlinked_work_directory(self) -> None:
        target = self.temp.path / "elsewhere"
        target.mkdir()
        os.symlink(target, claim.work_dir_path(self.temp.path, self.identity))
        with self.assertRaisesRegex(ValueError, "not an owned directory"):
            claim.cleanup(self.temp.path, self.identity)
        self.assertTrue(target.exists())

    def test_a_second_claim_for_the_same_run_refuses_to_reuse_state(self) -> None:
        claim.create_work_dir(self.temp.path, self.identity)
        with self.assertRaises(FileExistsError):
            claim.create_work_dir(self.temp.path, self.identity)


class ClaimCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.output = self.temp.path / "github_output"
        self.output.write_text("")
        self.runner_temp = self.temp.path / "runner-temp"
        self.runner_temp.mkdir()
        self.env = {**ENV, "RUNNER_TEMP": str(self.runner_temp), "GITHUB_OUTPUT": str(self.output)}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_claim_writes_step_outputs_for_the_upload(self) -> None:
        opener = RecordingOpener([FakeResponse(200, response())])
        code = claim.main(["claim", "--max-sources", "0"], env=self.env, opener=opener)
        self.assertEqual(code, 0)
        outputs = dict(line.split("=", 1) for line in self.output.read_text().splitlines())
        self.assertEqual(outputs["upload-provider"], "gcp_wif")
        self.assertEqual(outputs["workload-identity-provider"], UPLOAD["workloadIdentityProvider"])
        self.assertEqual(outputs["service-account"], UPLOAD["serviceAccount"])
        self.assertEqual(outputs["object-prefix"], UPLOAD["objectPrefix"])
        self.assertEqual(outputs["bucket"], UPLOAD["bucket"])
        work = Path(outputs["work-dir"])
        self.assertTrue((work / "in" / "inputs.json").is_file())

    def test_missing_settings_fail_with_their_names(self) -> None:
        env = {key: value for key, value in self.env.items() if key != "II_OS_TOKEN"}
        with self.assertRaisesRegex(claim.SettingError, "II_OS_TOKEN"):
            claim.main(["claim", "--max-sources", "0"], env=env, opener=RecordingOpener([]))


if __name__ == "__main__":
    unittest.main()
