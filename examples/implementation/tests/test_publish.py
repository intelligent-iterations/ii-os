"""The publish half of the generation contract: validate what the container
wrote, upload it to the workspace bucket, and report a terminal status."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import unittest

from tests.support import FakeResponse, RecordingOpener, TempDir, json_body, load
from tests.test_claim import ENV, UPLOAD

connector = load("scripts/ii_os_connector.py", "ii_os_connector")
publish = load("scripts/ii_os_publish.py", "ii_os_publish")

PNG = b"\x89PNG\r\n\x1a\n" + b"\x01" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x02" * 64
MP4 = b"\x00\x00\x00\x18ftypisom" + b"\x03" * 64
WAV = b"RIFF\x24\x00\x00\x00WAVEfmt " + b"\x04" * 64
MP3 = b"ID3\x04\x00\x00" + b"\x05" * 64
PREFIX = UPLOAD["objectPrefix"]
IMAGES = ("image/png", "image/jpeg", "image/webp")


class PlanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.work = self.temp.path / "work"
        (self.work / "out").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write(self, name: str, data: bytes) -> Path:
        path = self.work / "out" / name
        path.write_bytes(data)
        return path

    def result(self, *artifacts: dict[str, object], schema_version: int = 1) -> None:
        self.write("result.json", json.dumps({"schema_version": schema_version, "artifacts": list(artifacts)}).encode())

    def plan(self, allowed: tuple[str, ...] = IMAGES, max_bytes: int = 52428800) -> list:
        return publish.plan(
            self.work,
            object_prefix=PREFIX,
            run_id=987654321,
            run_attempt=1,
            allowed_content_types=allowed,
            max_bytes=max_bytes,
        )

    def test_plans_one_object_per_artifact_under_the_request_prefix(self) -> None:
        self.write("image.png", PNG)
        self.result({"file": "image.png", "contentType": "image/png"})
        [artifact] = self.plan()
        self.assertEqual(artifact.object_name, f"{PREFIX}image/image-987654321-1.png")
        self.assertEqual(artifact.content_type, "image/png")
        self.assertEqual(artifact.size_bytes, len(PNG))
        self.assertEqual(artifact.sha256, hashlib.sha256(PNG).hexdigest())

    def test_a_missing_result_manifest_fails_by_name(self) -> None:
        with self.assertRaisesRegex(ValueError, "result.json"):
            self.plan()

    def test_an_unknown_manifest_version_fails(self) -> None:
        self.write("image.png", PNG)
        self.result({"file": "image.png", "contentType": "image/png"}, schema_version=2)
        with self.assertRaisesRegex(ValueError, "schema_version"):
            self.plan()

    def test_artifact_names_may_not_leave_the_output_folder(self) -> None:
        (self.work / "secret.txt").write_bytes(PNG)
        for name in ("../secret.txt", "/etc/passwd", "sub/image.png", ".hidden.png", "", "a" * 200):
            with self.subTest(name=name):
                self.result({"file": name, "contentType": "image/png"})
                with self.assertRaisesRegex(ValueError, "file name"):
                    self.plan()

    def test_a_symlinked_artifact_is_refused(self) -> None:
        outside = self.temp.path / "outside.png"
        outside.write_bytes(PNG)
        os.symlink(outside, self.work / "out" / "image.png")
        self.result({"file": "image.png", "contentType": "image/png"})
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.plan()

    def test_a_content_type_the_catalog_does_not_declare_is_refused(self) -> None:
        self.write("clip.mp4", MP4)
        self.result({"file": "clip.mp4", "contentType": "video/mp4"})
        with self.assertRaisesRegex(ValueError, "video/mp4 is not an output this workflow declares"):
            self.plan()

    def test_bytes_that_do_not_match_the_declared_type_are_refused(self) -> None:
        self.write("image.png", JPEG)
        self.result({"file": "image.png", "contentType": "image/png"})
        with self.assertRaisesRegex(ValueError, "does not look like image/png"):
            self.plan()

    def test_the_extension_must_match_the_declared_type(self) -> None:
        self.write("image.jpg", PNG)
        self.result({"file": "image.jpg", "contentType": "image/png"})
        with self.assertRaisesRegex(ValueError, "extension"):
            self.plan()

    def test_an_artifact_over_the_catalog_ceiling_is_refused(self) -> None:
        self.write("image.png", PNG)
        self.result({"file": "image.png", "contentType": "image/png"})
        with self.assertRaisesRegex(ValueError, "larger than"):
            self.plan(max_bytes=10)

    def test_empty_and_duplicate_outputs_are_refused(self) -> None:
        self.write("empty.png", b"")
        self.result({"file": "empty.png", "contentType": "image/png"})
        with self.assertRaisesRegex(ValueError, "empty"):
            self.plan()
        self.write("image.png", PNG)
        self.result({"file": "image.png", "contentType": "image/png"}, {"file": "image.png", "contentType": "image/png"})
        with self.assertRaisesRegex(ValueError, "twice"):
            self.plan()
        self.result()
        with self.assertRaisesRegex(ValueError, "1 to 20"):
            self.plan()

    def test_a_poster_points_at_the_video_it_depicts(self) -> None:
        self.write("video.mp4", MP4)
        self.write("poster.jpg", JPEG)
        self.result(
            {"file": "video.mp4", "contentType": "video/mp4"},
            {"file": "poster.jpg", "contentType": "image/jpeg", "role": "poster", "posterFor": "video.mp4"},
        )
        video, poster = self.plan(allowed=("video/mp4", "image/jpeg"))
        self.assertEqual(poster.poster_for, video.object_name)
        self.assertEqual(poster.role, "poster")

    def test_a_poster_for_an_unknown_file_is_refused(self) -> None:
        self.write("poster.jpg", JPEG)
        self.result({"file": "poster.jpg", "contentType": "image/jpeg", "role": "poster", "posterFor": "video.mp4"})
        with self.assertRaisesRegex(ValueError, "poster"):
            self.plan(allowed=("video/mp4", "image/jpeg"))

    def test_audio_and_json_results_are_recognised(self) -> None:
        self.write("narration.wav", WAV)
        self.write("song.mp3", MP3)
        self.write("decisions.json", b'{"answers": {}}')
        self.result(
            {"file": "narration.wav", "contentType": "audio/wav"},
            {"file": "song.mp3", "contentType": "audio/mpeg"},
            {"file": "decisions.json", "contentType": "application/json"},
        )
        planned = self.plan(allowed=("audio/wav", "audio/mpeg", "application/json"))
        self.assertEqual(
            [item.object_name for item in planned],
            [
                f"{PREFIX}audio/narration-987654321-1.wav",
                f"{PREFIX}audio/song-987654321-1.mp3",
                f"{PREFIX}data/decisions-987654321-1.json",
            ],
        )

    def test_a_runner_may_name_the_object_path_a_documented_contract_expects(self) -> None:
        self.write("decisions.json", b'{"answers": {}}')
        self.result({"file": "decisions.json", "contentType": "application/json", "objectPath": "open-jev/decisions.json"})
        [planned] = self.plan(allowed=("application/json",))
        self.assertEqual(planned.object_name, f"{PREFIX}open-jev/decisions.json")

    def test_a_named_object_path_stays_under_the_request_prefix(self) -> None:
        self.write("decisions.json", b'{"answers": {}}')
        for path in ("../decisions.json", "/open-jev/decisions.json", "open-jev//decisions.json", "a/b/c/d.json",
                     "open-jev/decisions.png", "open-jev/.hidden.json", "open-jev/decisions"):
            with self.subTest(path=path):
                self.result({"file": "decisions.json", "contentType": "application/json", "objectPath": path})
                with self.assertRaisesRegex(ValueError, "object path"):
                    self.plan(allowed=("application/json",))

    def test_a_json_result_must_parse(self) -> None:
        self.write("decisions.json", b"{not json")
        self.result({"file": "decisions.json", "contentType": "application/json"})
        with self.assertRaisesRegex(ValueError, "does not look like application/json"):
            self.plan(allowed=("application/json",))


class UploadTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.file = self.temp.path / "image.png"
        self.file.write_bytes(PNG)
        self.artifact = publish.PlannedArtifact(
            path=self.file,
            object_name=f"{PREFIX}image/image-987654321-1.png",
            content_type="image/png",
            size_bytes=len(PNG),
            sha256=hashlib.sha256(PNG).hexdigest(),
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def session(self, location: str = "https://storage.googleapis.com/upload/storage/v1/b/example-app-assets/o?upload_id=abc") -> FakeResponse:
        return FakeResponse(200, b"", {"Location": location})

    def test_uploads_with_a_no_overwrite_precondition_and_the_sha256_metadata(self) -> None:
        stored = {"name": self.artifact.object_name, "size": str(len(PNG)), "generation": "1712345678901234"}
        opener = RecordingOpener([self.session(), FakeResponse(200, stored)])
        [reported] = publish.upload([self.artifact], bucket=UPLOAD["bucket"], access_token="example-access", opener=opener)
        init, put = opener.requests
        self.assertEqual(init["method"], "POST")
        self.assertIn("/upload/storage/v1/b/example-app-assets/o?", init["url"])
        self.assertIn("uploadType=resumable", init["url"])
        self.assertIn("ifGenerationMatch=0", init["url"])
        self.assertEqual(init["headers"]["authorization"], "Bearer example-access")
        self.assertEqual(json_body(init)["metadata"], {"ii-os-sha256": self.artifact.sha256})
        self.assertEqual(put["method"], "PUT")
        self.assertEqual(put["body"], PNG)
        self.assertEqual(
            reported,
            {
                "path": self.artifact.object_name,
                "contentType": "image/png",
                "sizeBytes": len(PNG),
                "sha256": self.artifact.sha256,
                "generation": "1712345678901234",
            },
        )

    def test_a_session_on_another_host_is_never_sent_the_file(self) -> None:
        opener = RecordingOpener([self.session("https://example.com/steal")])
        with self.assertRaisesRegex(ValueError, "upload session"):
            publish.upload([self.artifact], bucket=UPLOAD["bucket"], access_token="example-access", opener=opener)
        self.assertEqual(len(opener.requests), 1)

    def test_a_stored_size_mismatch_fails(self) -> None:
        stored = {"name": self.artifact.object_name, "size": "1", "generation": "17"}
        opener = RecordingOpener([self.session(), FakeResponse(200, stored)])
        with self.assertRaisesRegex(ValueError, "size"):
            publish.upload([self.artifact], bucket=UPLOAD["bucket"], access_token="example-access", opener=opener)

    def test_an_existing_object_is_not_overwritten(self) -> None:
        opener = RecordingOpener([FakeResponse(412, {"error": {"message": "conditionNotMet"}})])
        with self.assertRaisesRegex(ValueError, "already exists"):
            publish.upload([self.artifact], bucket=UPLOAD["bucket"], access_token="example-access", opener=opener)


class ReportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.identity = connector.RunIdentity.from_env(ENV)

    def client(self, opener: RecordingOpener):
        return connector.Connector(ENV["II_OS_CONNECTOR_URL"], "example-token", opener=opener)

    def test_reports_failure_directly_when_this_run_already_claimed(self) -> None:
        opener = RecordingOpener([FakeResponse(200, {"data": {"status": "failed"}})])
        outcome = publish.report_failure(self.client(opener), self.identity, status="failed", error_code="image_generation_failed")
        self.assertEqual(outcome, "reported")
        self.assertEqual(len(opener.requests), 1)
        self.assertTrue(opener.requests[0]["url"].endswith("/complete"))

    def test_claims_first_when_the_run_never_claimed(self) -> None:
        mismatch = {"error": {"code": "workflow_run_identity_mismatch", "message": "x"}}
        opener = RecordingOpener(
            [FakeResponse(409, mismatch), FakeResponse(200, {"data": {}}), FakeResponse(200, {"data": {}})]
        )
        outcome = publish.report_failure(self.client(opener), self.identity, status="cancelled", error_code="image_generation_cancelled")
        self.assertEqual(outcome, "reported")
        self.assertEqual(
            [request["url"].rsplit("route=", 1)[1] for request in opener.requests],
            [
                "v1/workflow-runs/req_0123456789abcdef/complete",
                "v1/workflow-runs/claim",
                "v1/workflow-runs/req_0123456789abcdef/complete",
            ],
        )
        self.assertEqual(json_body(opener.requests[2])["status"], "cancelled")

    def test_a_consumed_ghost_payload_still_lets_this_run_report(self) -> None:
        mismatch = {"error": {"code": "workflow_run_identity_mismatch", "message": "x"}}
        consumed = {"error": {"code": "ghost_payload_consumed", "message": "x"}}
        opener = RecordingOpener([FakeResponse(409, mismatch), FakeResponse(409, consumed), FakeResponse(200, {"data": {}})])
        self.assertEqual(
            publish.report_failure(self.client(opener), self.identity, status="failed", error_code="image_generation_failed"),
            "reported",
        )

    def test_an_already_terminal_request_is_left_alone(self) -> None:
        done = {"error": {"code": "workflow_run_already_completed", "message": "x"}}
        opener = RecordingOpener([FakeResponse(409, done)])
        self.assertEqual(
            publish.report_failure(self.client(opener), self.identity, status="failed", error_code="image_generation_failed"),
            "already-terminal",
        )

    def test_a_request_owned_by_another_run_is_left_alone(self) -> None:
        mismatch = {"error": {"code": "workflow_run_identity_mismatch", "message": "x"}}
        other = {"error": {"code": "workflow_run_already_claimed", "message": "x"}}
        opener = RecordingOpener([FakeResponse(409, mismatch), FakeResponse(409, other)])
        self.assertEqual(
            publish.report_failure(self.client(opener), self.identity, status="failed", error_code="image_generation_failed"),
            "not-owned",
        )

    def test_any_other_rejection_fails_the_step(self) -> None:
        opener = RecordingOpener([FakeResponse(403, {"error": {"code": "workflow_token_scope_mismatch", "message": "x"}})])
        with self.assertRaises(connector.ConnectorError):
            publish.report_failure(self.client(opener), self.identity, status="failed", error_code="image_generation_failed")

    def test_a_runner_failure_code_is_used_only_when_the_workflow_allows_it(self) -> None:
        temp = TempDir()
        try:
            out = temp.path / "out"
            out.mkdir()
            (out / "failure.json").write_text(json.dumps({"errorCode": "classification_request_rejected"}))
            self.assertEqual(
                publish.failure_code(temp.path, default="classification_workflow_failed", allowed=("classification_request_rejected",)),
                "classification_request_rejected",
            )
            self.assertEqual(
                publish.failure_code(temp.path, default="classification_workflow_failed", allowed=()),
                "classification_workflow_failed",
            )
            (out / "failure.json").write_text("not json")
            self.assertEqual(
                publish.failure_code(temp.path, default="x_failed", allowed=("classification_request_rejected",)),
                "x_failed",
            )
        finally:
            temp.cleanup()


class CompleteCommandTest(unittest.TestCase):
    def test_complete_sends_the_uploaded_artifacts(self) -> None:
        temp = TempDir()
        try:
            uploaded = [{"path": f"{PREFIX}image/image-987654321-1.png", "contentType": "image/png", "sizeBytes": 3, "sha256": "a" * 64, "generation": "17"}]
            (temp.path / "uploaded.json").write_text(json.dumps(uploaded))
            opener = RecordingOpener([FakeResponse(200, {"data": {"status": "completed"}})])
            code = publish.main(["complete", "--work-dir", str(temp.path)], env=ENV, opener=opener)
            self.assertEqual(code, 0)
            body = json_body(opener.requests[0])
            self.assertEqual(body["status"], "completed")
            self.assertIsNone(body["errorCode"])
            self.assertEqual(body["artifacts"], uploaded)
        finally:
            temp.cleanup()


if __name__ == "__main__":
    unittest.main()
