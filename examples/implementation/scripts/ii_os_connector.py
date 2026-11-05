"""HTTP client for the ii-os workflow-run connector.

A generation workflow talks to ii-os twice: it claims its request (proving the
exact GitHub run that ii-os dispatched) and later completes it with a terminal
status and the artifacts it uploaded. Both calls authenticate with the
workspace-scoped `II_OS_TOKEN`; ii-os independently verifies the run identity
against the GitHub API, so the body below is a claim, not a credential.

Standard library only: the same module runs on the self-hosted runner and in
the offline unit tests.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Any, Callable, Mapping
import urllib.error
import urllib.parse
import urllib.request

REQUEST_ID = re.compile(r"^[A-Za-z0-9_.:-]{8,64}$")
ERROR_CODE = re.compile(r"^[A-Za-z0-9_.:-]{1,100}$")
POSITIVE_INTEGER = re.compile(r"^[1-9][0-9]{0,19}$")
COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")
TERMINAL_STATUSES = ("completed", "failed", "cancelled")
TIMEOUT_SECONDS = 60

Opener = Callable[..., Any]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # A workspace credential is valid only at the configured connector.
        # urllib otherwise retains Authorization when redirecting POST to GET.
        return None


class ConnectorError(RuntimeError):
    """ii-os answered with an error; `code` is its stable error code."""

    def __init__(self, status: int, code: str, message: str):
        super().__init__(f"ii-os answered {status}: {code}: {message}")
        self.status = status
        self.code = code
        self.message = message


@dataclass(frozen=True)
class RunIdentity:
    request_id: str
    repository: str
    repository_id: int
    workflow_ref: str
    commit_sha: str
    run_id: int
    run_attempt: int

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "RunIdentity":
        request_id = env.get("II_REQUEST_ID", "").strip()
        if not REQUEST_ID.fullmatch(request_id):
            raise ValueError("II_REQUEST_ID is not a request id ii-os issues")
        repository = _required(env, "GITHUB_REPOSITORY")
        if repository.count("/") != 1:
            raise ValueError("GITHUB_REPOSITORY must be owner/name")
        commit_sha = _required(env, "GITHUB_SHA").lower()
        if not COMMIT_SHA.fullmatch(commit_sha):
            raise ValueError("GITHUB_SHA must be a full commit SHA")
        return cls(
            request_id=request_id,
            repository=repository,
            repository_id=_positive(env, "GITHUB_REPOSITORY_ID"),
            workflow_ref=_required(env, "GITHUB_WORKFLOW_REF"),
            commit_sha=commit_sha,
            run_id=_positive(env, "GITHUB_RUN_ID"),
            run_attempt=_positive(env, "GITHUB_RUN_ATTEMPT"),
        )

    def claim_body(self) -> dict[str, Any]:
        return {
            "requestId": self.request_id,
            "repository": self.repository,
            "repositoryId": self.repository_id,
            "workflowRef": self.workflow_ref,
            "commitSha": self.commit_sha,
            "runId": self.run_id,
            "runAttempt": self.run_attempt,
        }

    def owner_record(self) -> dict[str, Any]:
        """What an ownership marker records: one request, one run attempt."""
        return {
            "schema": "ii-os-workflow-run-v1",
            "request_id": self.request_id,
            "repository": self.repository,
            "run_id": self.run_id,
            "run_attempt": self.run_attempt,
        }


class Connector:
    def __init__(self, base_url: str, token: str, *, opener: Opener | None = None):
        self.base_url = validate_connector_url(base_url)
        if not token or not token.strip():
            raise ValueError("II_OS_TOKEN is empty")
        self._token = token.strip()
        self._open = opener or urllib.request.build_opener(_NoRedirect()).open

    def claim(self, identity: RunIdentity) -> dict[str, Any]:
        return self._post("v1/workflow-runs/claim", identity.claim_body())

    def complete(
        self,
        identity: RunIdentity,
        *,
        status: str,
        error_code: str | None = None,
        artifacts: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        if status not in TERMINAL_STATUSES:
            raise ValueError(f"status must be one of {', '.join(TERMINAL_STATUSES)}")
        if status == "completed":
            if error_code is not None:
                raise ValueError("a completed run carries no error code")
            if not artifacts:
                raise ValueError("a completed run must report at least one artifact")
        elif error_code is None or not ERROR_CODE.fullmatch(error_code):
            raise ValueError("a failed or cancelled run needs a stable error code")
        body = {
            "runId": identity.run_id,
            "runAttempt": identity.run_attempt,
            "status": status,
            "errorCode": error_code,
            "artifacts": artifacts or [],
        }
        route = f"v1/workflow-runs/{urllib.parse.quote(identity.request_id, safe='')}/complete"
        return self._post(route, body)

    def _post(self, route: str, body: dict[str, Any]) -> dict[str, Any]:
        request = urllib.request.Request(
            f"{self.base_url}?route={route}",
            data=json.dumps(body, separators=(",", ":")).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with self._open(request, timeout=TIMEOUT_SECONDS) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            raise _connector_error(error) from None
        except urllib.error.URLError as error:
            raise ConnectorError(0, "connector_unreachable", str(error.reason)) from None
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            raise ConnectorError(200, "invalid_response", "ii-os returned a body that is not JSON") from None
        data = payload.get("data") if isinstance(payload, dict) else None
        if not isinstance(data, dict):
            raise ConnectorError(200, "invalid_response", "ii-os returned no data object")
        return data


def validate_connector_url(value: str) -> str:
    base = (value or "").strip().rstrip("/")
    parsed = urllib.parse.urlparse(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.query or parsed.fragment:
        raise ValueError("II_OS_CONNECTOR_URL must be an https URL with no query, for example https://ii-os.example.com/api")
    return base


def _connector_error(error: urllib.error.HTTPError) -> ConnectorError:
    code, message = "unknown", "No error body"
    try:
        payload = json.loads(error.read().decode("utf-8"))
        detail = payload.get("error") if isinstance(payload, dict) else None
        if isinstance(detail, dict):
            if isinstance(detail.get("code"), str) and ERROR_CODE.fullmatch(detail["code"]):
                code = detail["code"]
            if isinstance(detail.get("message"), str):
                message = detail["message"][:300]
    except (ValueError, OSError, AttributeError):
        pass
    finally:
        error.close()
    return ConnectorError(error.code, code, message)


def _required(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise ValueError(f"{name} is not set")
    return value


def _positive(env: Mapping[str, str], name: str) -> int:
    value = _required(env, name)
    if not POSITIVE_INTEGER.fullmatch(value):
        raise ValueError(f"{name} must be a positive integer")
    return int(value)
