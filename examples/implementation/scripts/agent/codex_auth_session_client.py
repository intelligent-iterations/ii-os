"""Bounded Codex device-auth client used by the trusted agent controller.

Contract:
- ``II_OS_CONNECTOR_URL`` is the ii-os API base. It must be an https URL
  without userinfo, query or fragment; plain http is accepted only for a
  loopback (``localhost``/``127.0.0.1``) test server. Callbacks are sent to
  ``<II_OS_CONNECTOR_URL>?route=<route>`` with a GitHub Actions OIDC token
  whose audience is ``<II_OS_CONNECTOR_URL>/v1/codex-auth-sessions``.
- Callback bodies carry status metadata only. OAuth bytes stay in 0600 files
  and are never placed in argv, callback bodies, logs or exception text.
"""

from __future__ import annotations

import json
import os
import queue
import re
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


SCRIPTS = Path(__file__).resolve().parent
DEVICE_URL = "https://auth.openai.com/codex/device"
CONNECTOR_SETTING = "II_OS_CONNECTOR_URL"
OIDC_AUDIENCE_ROUTE = "/v1/codex-auth-sessions"
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1"})
MAX_GITHUB_OIDC_REQUEST_TOKEN_CHARS = 16384
MAX_RESPONSE_BYTES = 65536
USER_CODE = re.compile(r"^[A-Z0-9]{4}-[A-Z0-9]{4,8}$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SESSION_ID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-"
    r"[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
# Non-secret controller settings forwarded to the trusted Node adapters
# (runtime_codex_smoke.mjs and codex_credential_rotation.mjs).
CONTROLLER_SETTINGS = (
    CONNECTOR_SETTING,
    "II_OS_AGENT_EXECUTION_DIR",
    "II_OS_CONTROLLER_STATE_DIR",
    "II_OS_CONTROLLER_ADMISSION_DIR",
    "II_OS_CONTROLLER_SCRATCH_DIR",
)


class SessionFailure(RuntimeError):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


def sanitized_environment(
    *,
    codex_home: Path | None = None,
    source: dict[str, str] | None = None,
) -> dict[str, str]:
    source_env = os.environ if source is None else source
    allowed = (
        "PATH", "LANG", "LC_ALL", "TZ", "TMPDIR", "TEMP", "TMP",
        "SSL_CERT_FILE", "SSL_CERT_DIR",
    )
    env = {name: source_env[name] for name in allowed if source_env.get(name)}
    if codex_home is not None:
        env["CODEX_HOME"] = str(codex_home)
        env["HOME"] = str(codex_home.parent)
    return env


def require_subscription_oauth(value: Any) -> None:
    """Accept only a Codex subscription OAuth cache; never an API key."""
    tokens = value.get("tokens") if isinstance(value, dict) else None
    if (not isinstance(tokens, dict) or value.get("OPENAI_API_KEY")
            or value.get("auth_mode") not in (None, "chatgpt")
            or any(not isinstance(tokens.get(key), str) or not tokens[key].strip()
                   for key in ("access_token", "refresh_token"))):
        raise ValueError("subscription OAuth required")


class CodexAppServer:
    def __init__(self, codex_home: Path) -> None:
        self._messages: queue.Queue[dict[str, Any]] = queue.Queue()
        self._stderr: list[str] = []
        self._process = subprocess.Popen(
            ["codex", "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=sanitized_environment(codex_home=codex_home),
            start_new_session=True,
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def initialize(self) -> None:
        self.send(
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": "ii_os",
                        "title": "ii-os",
                        "version": "1.0.0",
                    }
                },
            }
        )
        response = self.wait_for(lambda item: item.get("id") == 1, 30)
        self._require_result(response, "codex_app_server_initialize_failed")
        self.send({"method": "initialized", "params": {}})

    def start_device_login(self) -> tuple[str, str, str]:
        self.send(
            {
                "method": "account/login/start",
                "id": 2,
                "params": {"type": "chatgptDeviceCode"},
            }
        )
        response = self.wait_for(lambda item: item.get("id") == 2, 30)
        result = self._require_result(
            response,
            "codex_device_challenge_failed",
        )
        login_id = result.get("loginId")
        verification_url = result.get("verificationUrl")
        user_code = result.get("userCode")
        if (
            not isinstance(login_id, str)
            or not login_id
            or verification_url != DEVICE_URL
            or not isinstance(user_code, str)
            or not USER_CODE.fullmatch(user_code)
        ):
            raise SessionFailure(
                "codex_device_challenge_invalid",
                "Codex returned an invalid OpenAI sign-in challenge.",
            )
        return login_id, verification_url, user_code

    def wait_for_login(self, login_id: str) -> None:
        def completed(item: dict[str, Any]) -> bool:
            params = item.get("params")
            return (
                item.get("method") == "account/login/completed"
                and isinstance(params, dict)
                and params.get("loginId") == login_id
            )

        event = self.wait_for(completed, 14 * 60 + 30)
        params = event.get("params")
        if not isinstance(params, dict) or params.get("success") is not True:
            raise SessionFailure(
                "codex_login_failed",
                "OpenAI did not complete the Codex sign-in.",
            )

    def send(self, message: dict[str, Any]) -> None:
        if self._process.stdin is None:
            raise SessionFailure(
                "codex_app_server_closed",
                "Codex closed before sign-in completed.",
            )
        self._process.stdin.write(
            json.dumps(message, separators=(",", ":")) + "\n"
        )
        self._process.stdin.flush()

    def wait_for(self, predicate: Any, timeout: float) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self._process.poll() is not None and self._messages.empty():
                raise SessionFailure(
                    "codex_app_server_failed",
                    "Codex stopped before sign-in completed.",
                )
            try:
                item = self._messages.get(
                    timeout=max(0.01, min(1, deadline - time.monotonic()))
                )
            except queue.Empty:
                continue
            if predicate(item):
                return item
        raise SessionFailure(
            "codex_login_expired",
            "The OpenAI sign-in window expired. Start a new sign-in.",
        )

    def close(self) -> None:
        if self._process.poll() is not None:
            return
        try:
            os.killpg(self._process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            self._process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self._process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self._process.wait(timeout=5)

    def _read_stdout(self) -> None:
        if self._process.stdout is None:
            return
        for line in self._process.stdout:
            try:
                decoded = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(decoded, dict):
                self._messages.put(decoded)

    def _read_stderr(self) -> None:
        if self._process.stderr is None:
            return
        for line in self._process.stderr:
            self._stderr.append(line[-500:])
            del self._stderr[:-20]

    @staticmethod
    def _require_result(
        response: dict[str, Any],
        error_code: str,
    ) -> dict[str, Any]:
        result = response.get("result")
        if "error" in response or not isinstance(result, dict):
            raise SessionFailure(
                error_code,
                "Codex could not start the OpenAI sign-in flow.",
            )
        return result


def configured_connector(source: dict[str, str] | None = None) -> str:
    """Return the validated ii-os API base named by II_OS_CONNECTOR_URL."""
    source_env = os.environ if source is None else source
    value = source_env.get(CONNECTOR_SETTING, "")
    if not value.strip():
        raise SessionFailure(
            "ii_os_connector_missing",
            "II_OS_CONNECTOR_URL is not configured.",
        )
    try:
        uri = urllib.parse.urlparse(value)
        hostname = uri.hostname
        uri.port  # Raises for an invalid port.
    except ValueError:
        hostname = None
    if (
        not hostname
        or uri.scheme not in {"https", "http"}
        or "@" in uri.netloc
        or uri.params
        or uri.query
        or uri.fragment
        or "?" in value
        or "#" in value
        or value.endswith("/")
        or not re.fullmatch(r"[\x21-\x7e]+", value)
    ):
        raise SessionFailure(
            "ii_os_connector_invalid",
            "II_OS_CONNECTOR_URL must be an https URL without credentials, "
            "query, fragment or trailing slash.",
        )
    if uri.scheme != "https" and hostname not in LOOPBACK_HOSTS:
        raise SessionFailure(
            "ii_os_connector_invalid",
            "II_OS_CONNECTOR_URL must use HTTPS.",
        )
    return value


def oidc_audience() -> str:
    return configured_connector() + OIDC_AUDIENCE_ROUTE


def connector_url(base: str, route: str) -> str:
    connector = configured_connector()
    if base != connector:
        raise SessionFailure(
            "ii_os_connector_invalid",
            "The callback is not addressed to II_OS_CONNECTOR_URL.",
        )
    if (
        not re.fullmatch(r"v1/[A-Za-z0-9_./-]+", route)
        or ".." in route
        or "//" in route
    ):
        raise SessionFailure(
            "ii_os_connector_invalid",
            "The ii-os callback route is invalid.",
        )
    return connector + "?" + urllib.parse.urlencode({"route": route})


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str,
                         headers: Any, newurl: str) -> None:
        return None


class _ResponseTooLarge(ValueError):
    pass


def _read_json(response: Any) -> Any:
    """Decode at most MAX_RESPONSE_BYTES of a JSON response body."""
    raw = response.read(MAX_RESPONSE_BYTES + 1)
    if len(raw) > MAX_RESPONSE_BYTES:
        raise _ResponseTooLarge("response exceeds the bounded size")
    return json.loads(raw.decode())


def valid_github_oidc_request_url(value: str) -> bool:
    uri = urllib.parse.urlparse(value)
    return (
        uri.scheme == "https"
        and bool(uri.hostname)
        and (
            uri.hostname == "actions.githubusercontent.com"
            or uri.hostname.endswith(".actions.githubusercontent.com")
        )
        and uri.username is None
        and uri.password is None
        and not uri.fragment
    )


def github_oidc_request(
    source: dict[str, str] | None = None,
) -> tuple[str, str]:
    source_env = os.environ if source is None else source
    request_url = source_env.get(
        "ACTIONS_ID_TOKEN_REQUEST_URL", ""
    ).strip()
    request_token = source_env.get(
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN", ""
    ).strip()
    if not request_url or not request_token:
        raise SessionFailure(
            "github_actions_oidc_missing",
            "GitHub Actions did not provide a workload identity.",
        )
    if (
        not valid_github_oidc_request_url(request_url)
        or len(request_token) > MAX_GITHUB_OIDC_REQUEST_TOKEN_CHARS
    ):
        raise SessionFailure(
            "github_actions_oidc_invalid",
            "GitHub Actions provided an invalid workload identity request.",
        )
    return request_url, request_token


def github_oidc_token() -> str:
    request_url, request_token = github_oidc_request()
    separator = "&" if "?" in request_url else "?"
    url = request_url + separator + urllib.parse.urlencode(
        {"audience": oidc_audience()}
    )
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {request_token}",
        },
    )
    try:
        # Never forward the request token to a redirect target.
        with urllib.request.build_opener(_NoRedirect()).open(
            request, timeout=20
        ) as response:
            decoded = _read_json(response)
    except (urllib.error.URLError, ValueError, UnicodeDecodeError) as error:
        raise SessionFailure(
            "github_actions_oidc_failed",
            "GitHub Actions could not issue its workload identity.",
        ) from error
    token = decoded.get("value") if isinstance(decoded, dict) else None
    if not isinstance(token, str) or not 100 <= len(token) <= 12000:
        raise SessionFailure(
            "github_actions_oidc_failed",
            "GitHub Actions returned an invalid workload identity.",
        )
    return token


def post_json(
    base: str,
    route: str,
    body: dict[str, Any],
    *,
    identity_token: str | None = None,
    attempts: int = 3,
) -> dict[str, Any]:
    if attempts < 1 or attempts > 3:
        raise ValueError("attempts must be between 1 and 3")
    url = connector_url(base, route)
    last_error: BaseException | None = None
    for attempt in range(attempts):
        charge_callback()
        request = urllib.request.Request(
            url,
            data=json.dumps(body, separators=(",", ":")).encode(),
            method="POST",
            headers={
                "Accept": "application/json",
                "Authorization": (
                    f"Bearer {identity_token or github_oidc_token()}"
                ),
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.build_opener(_NoRedirect()).open(
                request, timeout=30
            ) as response:
                if response.geturl() != url:
                    raise SessionFailure(
                        "ii_os_callback_redirected",
                        "ii-os redirected a credential-bearing callback.",
                    )
                try:
                    decoded = _read_json(response)
                except _ResponseTooLarge as error:
                    raise SessionFailure(
                        "ii_os_callback_failed",
                        "ii-os returned an oversized sign-in response.",
                    ) from error
            if not isinstance(decoded, dict):
                raise SessionFailure(
                    "ii_os_callback_failed",
                    "ii-os returned an invalid sign-in response.",
                )
            return decoded
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code < 500:
                break
        except (urllib.error.URLError, ValueError, UnicodeDecodeError) as error:
            last_error = error
        if attempt + 1 < attempts:
            time.sleep(1 + attempt)
    raise SessionFailure(
        "ii_os_callback_failed",
        "ii-os could not record the Codex sign-in status.",
    ) from last_error


def controller_state_dir() -> Path:
    """The controller's persistent private directory (absolute, normalized)."""
    value = os.environ.get("II_OS_CONTROLLER_STATE_DIR", "")
    if (not value or not os.path.isabs(value) or value == "/"
            or os.path.normpath(value) != value):
        raise ValueError("II_OS_CONTROLLER_STATE_DIR must be an absolute directory")
    return Path(value)


def controller_settings() -> dict[str, str]:
    return {
        name: os.environ[name]
        for name in CONTROLLER_SETTINGS
        if os.environ.get(name)
    }


def charge_callback() -> None:
    context = os.environ.get("II_OS_CREDENTIAL_BUDGET_CONTEXT")
    if context is None:
        if os.environ.get("II_OS_RUNTIME_KIND") in {"codex-auth", "codex-auth-verify"}:
            raise SessionFailure("credential_budget_invalid", "The runtime credential callback budget is missing.")
        return
    try:
        expected = controller_state_dir() / "credential-rotation" / "context.json"
    except ValueError as error:
        raise SessionFailure(
            "credential_budget_invalid", "II_OS_CONTROLLER_STATE_DIR must be an absolute directory.",
        ) from error
    if context != str(expected):
        raise SessionFailure("credential_budget_invalid", "The credential callback budget is not bound to this runtime.")
    environment = sanitized_environment()
    environment.update(controller_settings())
    environment["II_OS_CREDENTIAL_BUDGET_CONTEXT"] = context
    try:
        result = subprocess.run(
            ["node", str(SCRIPTS / "codex_credential_rotation.mjs"), "charge"],
            env=environment, capture_output=True, timeout=15, check=False,
        )
        if result.returncode != 0:
            raise OSError("credential debit unconfirmed")
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SessionFailure(
            "credential_budget_exhausted", "The bounded credential callback allowance could not be confirmed.",
        ) from error


def run_metadata() -> dict[str, Any]:
    server = os.environ.get(
        "GITHUB_SERVER_URL", "https://github.com"
    ).rstrip("/")
    if server != "https://github.com":
        raise SessionFailure(
            "codex_auth_configuration_missing",
            "The GitHub workflow origin is invalid.",
        )
    repository = os.environ["GITHUB_REPOSITORY"]
    run_id = int(os.environ["GITHUB_RUN_ID"])
    run_attempt = int(os.environ.get("GITHUB_RUN_ATTEMPT", "1"))
    return {
        "runId": run_id,
        "runAttempt": run_attempt,
        "runUrl": (
            f"{server}/{repository}/actions/runs/{run_id}/"
            f"attempts/{run_attempt}"
        ),
    }


def smoke_codex(codex_home: Path, smoke_dir: Path) -> None:
    environment = sanitized_environment(codex_home=codex_home)
    for key in (
        "GITHUB_REPOSITORY", "GITHUB_REPOSITORY_ID", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT",
        "COORDINATOR_SOURCE_SHA", "II_OS_RUNTIME_SOURCE_SHA", "II_OS_RUNTIME_CONTROLLER",
        "II_OS_RUNTIME_KIND", "II_OS_CODEX_AUTH_SESSION_ID",
        "II_OS_RUNTIME_OBSERVER", "II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER",
        "II_OS_CREDENTIAL_BUDGET_CONTEXT", "II_OS_CREDENTIAL_ROTATION_OIDC",
        *CONTROLLER_SETTINGS,
    ):
        if key in os.environ:
            environment[key] = os.environ[key]
    try:
        result = subprocess.run(
            [
                "node", str(SCRIPTS / "runtime_codex_smoke.mjs"),
                "execute", str(codex_home / "auth.json"), str(smoke_dir),
            ],
            env=environment,
            text=True,
            capture_output=True,
            # The worker remains limited to three minutes. This includes
            # teardown and the bounded post-cleanup provider write/revocation.
            timeout=600,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise SessionFailure(
            "codex_auth_smoke_timeout",
            "OpenAI sign-in completed, but the verification request timed out.",
        ) from error
    output = smoke_dir / "ok.txt"
    if not (
        result.returncode != 0
        or not output.is_file()
        or output.read_text().strip() != "ok"
    ):
        return
    try:
        runtime_result = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        runtime_result = None
    runtime_result = runtime_result if isinstance(runtime_result, dict) else {}
    model_transcript = runtime_result.get("transcript")
    # Inspect output, never lifecycle metadata such as "network" cleanup.
    transcript = "\n".join(
        value for value in (model_transcript, result.stderr) if isinstance(value, str)
    ).lower()
    failures = (
        (("refresh_token_reused", "token_expired", "could not be refreshed"),
         "codex_auth_refresh_failed", "OpenAI accepted sign-in, but the new "
         "Codex credential could not be refreshed."),
        (("usage limit", "rate limit", "too many requests", "429"),
         "codex_auth_usage_limited", "OpenAI accepted sign-in, but this account "
         "cannot run a Codex request right now."),
        (("not logged in", "unauthorized", "authentication required", "401"),
         "codex_auth_request_unauthorized", "OpenAI accepted sign-in, but Codex "
         "did not recognize the saved credential."),
        (("network", "connection", "dns", "tls"),
         "codex_auth_network_failed", "OpenAI accepted sign-in, but the "
         "verification runner could not reach Codex."),
    )
    for markers, code, detail in failures:
        if any(marker in transcript for marker in markers):
            raise SessionFailure(code, detail)
    outcome = runtime_result.get("outcome")
    collection_failed = isinstance(outcome, dict) and (
        outcome.get("started") is True and outcome.get("cleanupConfirmed") is True
        and outcome.get("phase") == "collection" and outcome.get("status") == "failed"
    )
    if result.returncode == 0 or collection_failed:
        raise SessionFailure(
            "codex_auth_smoke_output_missing",
            "The Codex request did not complete the verification file.",
        )
    raise SessionFailure(
        "codex_auth_smoke_failed",
        "OpenAI sign-in completed, but a real Codex request failed.",
    )
