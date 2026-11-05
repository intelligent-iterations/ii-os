"""Resolve the workflow's frozen, consumed approval into runtime inputs.

Every value here is read at the trusted source revision ii-os approved, then
checked against the digests the approval carries. Nothing is fetched from a
moving branch except the dev commit the agent starts from.
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import urllib.parse
import urllib.request

from agent_task_profile import canonical_profile_digest, validate_executable_profile


SHA = re.compile(r"[a-f0-9]{40}")
DIGEST = re.compile(r"[a-f0-9]{64}")
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}")
SLUG = re.compile(r"[a-z0-9][a-z0-9-]{0,99}")
EXECUTABLE_PATH = "/usr/local/bin:/usr/bin:/bin"
# The reference labels this kit's runtime configurations bind. The values are
# delivered by the job's staged handoff; configuration holds only references.
CREDENTIAL_KEYS = [
    ("source", "source.read", "II_OS_GITHUB_APP_READ_TOKEN"),
    ("oauth", "harness.codex.oauth", "CODEX_AUTH_JSON"),
    ("usage", "usage.report", "II_OS_AGENT_USAGE_API_KEY"),
]


def api_base(environment):
    value = environment.get("GITHUB_API_URL") or "https://api.github.com"
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise RuntimeError("GitHub API endpoint is invalid")
    return value.rstrip("/") + "/"


def connector_url(environment):
    value = environment.get("II_OS_CONNECTOR_URL", "")
    parsed = urllib.parse.urlsplit(value)
    local = parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost"}
    if not (parsed.scheme == "https" or local) or not parsed.hostname or parsed.username or parsed.password \
            or parsed.query or parsed.fragment or value.endswith("/"):
        raise RuntimeError("II_OS_CONNECTOR_URL is not configured as an https URL")
    return value


def allocation(environment):
    """The operator's explicitly partitioned admission allocation."""
    try:
        value = json.loads(environment.get("II_OS_AGENT_ALLOCATION", ""))
    except ValueError:
        raise RuntimeError("II_OS_AGENT_ALLOCATION is not valid JSON") from None
    capacity = value.get("capacity") if isinstance(value, dict) else None
    if not isinstance(value, dict) or set(value) != {"allocationId", "monthlyLimit", "capacity"} \
            or not isinstance(value["allocationId"], str) or not IDENTIFIER.fullmatch(value["allocationId"]) \
            or type(value["monthlyLimit"]) is not int or not 1 <= value["monthlyLimit"] <= 10000 \
            or not isinstance(capacity, dict) or set(capacity) != {"cpu", "memoryMiB", "diskGiB"} \
            or any(type(capacity[key]) is not int or capacity[key] < 1 for key in capacity):
        raise RuntimeError("II_OS_AGENT_ALLOCATION must be {allocationId, monthlyLimit, capacity:{cpu, memoryMiB, diskGiB}}")
    return value


class GitHubInputs:
    def __init__(self, token, base="https://api.github.com/"):
        if not token:
            raise RuntimeError("scoped GitHub read credential is unavailable")
        self.token = token
        self.base = base

    def get(self, path):
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        request = urllib.request.Request(self.base + path, headers={
            "Authorization": "Bearer " + self.token, "Accept": "application/vnd.github+json",
        })
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
                encoded = response.read(1572865)
                if len(encoded) > 1572864:
                    raise RuntimeError("GitHub input exceeded its bound")
                return json.loads(encoded)
        except (OSError, ValueError):
            raise RuntimeError("approved GitHub source input is unavailable") from None

    def file(self, repository, path, revision):
        value = self.get("repos/" + repository + "/contents/" + urllib.parse.quote(path, safe="/") + "?ref=" + revision)
        if value.get("type") != "file" or value.get("encoding") != "base64":
            raise RuntimeError("approved source input is not a regular file")
        encoded = base64.b64decode(value["content"].replace("\n", ""), validate=True)
        if len(encoded) > 1048576:
            raise RuntimeError("approved source file exceeded its bound")
        return encoded


def resolve_inputs(environment, github):
    repository = environment.get("TARGET_REPOSITORY", "")
    source = environment.get("TRUSTED_SOURCE_SHA", "")
    permission = environment.get("PERMISSION_DIGEST", "")
    profile_id = environment.get("PERMISSION_PROFILE", "")
    slug = environment.get("II_OS_GITHUB_APP_SLUG", "")
    if not REPOSITORY.fullmatch(repository) or not SHA.fullmatch(source) or not DIGEST.fullmatch(permission) \
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", profile_id) or environment.get("PERMISSION_REF") != "dev" \
            or not SLUG.fullmatch(slug) or environment.get("GITHUB_API_APP_SLUG") != slug:
        raise RuntimeError("runtime workflow source identity is invalid")
    identity = {"repository": repository}
    for key, variable in {"repositoryId": "GITHUB_REPOSITORY_ID", "issueNumber": "ISSUE_NUMBER", "runId": "GITHUB_RUN_ID", "runAttempt": "GITHUB_RUN_ATTEMPT"}.items():
        value = environment.get(variable, "")
        if not re.fullmatch(r"[1-9][0-9]{0,15}", value) or int(value) > 9007199254740991:
            raise RuntimeError("runtime workflow numeric identity is invalid")
        identity[key] = int(value)
    for key, variable in {"dispatchId": "DISPATCH_ID", "projectItemId": "PROJECT_ITEM_ID", "workspaceId": "WORKSPACE_ID"}.items():
        value = environment.get(variable, "")
        if not IDENTIFIER.fullmatch(value):
            raise RuntimeError("runtime workflow dispatch identity is invalid")
        identity[key] = value
    remote = github.get("repos/" + repository)
    if remote.get("full_name") != repository or remote.get("id") != identity["repositoryId"]:
        raise RuntimeError("repository identity changed before deployment")
    profile = json.loads(github.file(repository, ".ii-os/agent-permissions/" + profile_id + ".json", source))
    validate_executable_profile(profile, expected_id=profile_id)
    if profile.get("schema_version") != 4 or canonical_profile_digest(profile) != permission or profile["workflow"] != {"file": "ii-os-agent-task.yml", "ref": "dev"}:
        raise RuntimeError("runtime permission profile changed after approval")
    if profile.get("engine") != "codex":
        raise RuntimeError("this kit runs only the codex engine; the approved profile names another engine")
    files, decoded = {}, {}
    for name, reference in profile["runtime"].items():
        encoded = github.file(repository, reference["path"], source)
        if hashlib.sha256(encoded).hexdigest() != reference["sha256"]:
            raise RuntimeError("approved runtime file changed")
        files[reference["path"]] = {"commit": source, "base64": base64.b64encode(encoded).decode()}
        decoded[name] = json.loads(encoded)
    configuration = decoded["configuration"]
    if configuration.get("source", {}).get("repository") != repository:
        raise RuntimeError("runtime configuration selects another source repository")
    if configuration["source"].get("additionalRepositories"):
        raise RuntimeError("this kit prepares only the approved repository; additional repositories are unsupported")
    # This is the already-consumed broker snapshot, not a new issue fetch.
    prompt = base64.b64decode(environment.get("IIAUTO_TICKET_PROMPT_B64", ""), validate=True)
    prompt_digest = environment.get("IIAUTO_TICKET_PROMPT_SHA256", "")
    if environment.get("IIAUTO_APPROVAL_CONSUMED") != "1" or not DIGEST.fullmatch(prompt_digest) or len(prompt) > 65536 or hashlib.sha256(prompt).hexdigest() != prompt_digest:
        raise RuntimeError("the exact consumed human approval is unavailable")
    snapshot = json.loads(prompt)
    if any(snapshot.get(key) != value for key, value in {"repository": repository, "repository_id": identity["repositoryId"], "issue_number": identity["issueNumber"], "project_item_id": identity["projectItemId"]}.items()):
        raise RuntimeError("approved prompt identifies another deployment")
    commit = github.get("repos/" + repository + "/git/ref/heads/dev").get("object", {}).get("sha", "")
    if not SHA.fullmatch(commit):
        raise RuntimeError("repository dev revision is unavailable")
    repositories = [{"repository": repository, "path": "", "commit": commit}]
    # GitHub Project mutations stay with the ii-os broker (deferred mode). The
    # worker policy only maps these fixed local labels to status names in its
    # bounded result; ii-os applies the real Project change at finalization.
    task = {"title": snapshot.get("title", ""), "appSlug": slug,
            "gitName": slug + "[bot]", "gitEmail": slug + "[bot]@users.noreply.github.com",
            "projectId": "deferred-project", "statusFieldId": "deferred-status", "todoOptionId": "todo",
            "inProgressOptionId": "in-progress", "readyOptionId": "ready-for-qa", "humanOptionId": "needs-human-input"}
    references = configuration.get("credentialBindings", [])
    bindings = {}
    for name, assignment, key in CREDENTIAL_KEYS:
        matches = [value for value in references if value.get("assignment") == assignment]
        if len(matches) != 1 or matches[0] != {"provider": "github-actions", "resource": repository, "key": key, "assignment": assignment}:
            raise RuntimeError("runtime credential assignment is unsupported")
        bindings[name] = {"reference": matches[0]}
    connector = connector_url(environment)
    settings = {"mode": "execute", "identity": identity, "task": task, "profile": profile, "permissionDigest": permission,
                "sourceRevision": source, "runtimeFiles": files, "repositories": repositories,
                "authorization": {"consumed": True, "repositoryId": identity["repositoryId"], "runId": identity["runId"], "dispatchId": identity["dispatchId"], "permissionDigest": permission, "sourceRevision": source, "ticketPromptDigest": prompt_digest},
                "connector": connector, "workflow": bindings}
    original_digest = environment.get("CODEX_SECRET_DIGEST", "")
    if not DIGEST.fullmatch(original_digest):
        raise RuntimeError("the approved OAuth snapshot digest is unavailable")
    configuration_path = profile["runtime"]["configuration"]["path"]
    settings["credentialRotation"] = {"originalDigest": original_digest,
        "runtimeConfiguration": base64.b64decode(files[configuration_path]["base64"]).decode("utf-8")}
    settings["workflow"]["reporter"] = {"executable": "/usr/local/bin/node", "executablePath": EXECUTABLE_PATH,
                                        "endpoint": connector, "workspaceId": identity["workspaceId"]}
    return {"settings": settings, "promptBase64": base64.b64encode(prompt).decode(), "configuration": configuration}


def github_from_environment(environment):
    return GitHubInputs(environment.get("GITHUB_API_TOKEN"), api_base(environment))

