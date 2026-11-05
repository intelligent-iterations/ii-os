#!/usr/bin/env python3
"""Crash-recoverable, inode-bound credential staging for one agent job.

Usage: agent_credential_handoff.py stage|cleanup|recover|recover-all

The handoff lives under ``${RUNNER_TEMP}/ii-os-agent-handoff``: ``stage/``
holds one private child directory per workflow run attempt and ``ledger/``
records each child's lifecycle phase so an interrupted stage or cleanup can be
resumed without guessing what it owns. Run with the repository root as the
working directory; reviewed worker sources are read from
``scripts/agent/worker/``.

``stage`` validates every input before touching the filesystem, writes each
file with mode 0600 into a 0700 directory, and appends
``II_OS_AGENT_HANDOFF_DIR``, ``II_OS_AGENT_HANDOFF_DEVICE``,
``II_OS_AGENT_HANDOFF_INODE`` and ``II_OS_AGENT_HANDOFF_DIGESTS`` to
``$GITHUB_ENV``. ``cleanup`` deletes only the exact directory those values
identify and appends ``proven=true`` to ``$GITHUB_OUTPUT``.
"""

import base64
import hashlib
import json
import os
import re
import stat
import sys
import time


HANDOFF_DIRECTORY = "ii-os-agent-handoff"
FILES = {
    "github-api.token": "API_TOKEN",
    "codex-auth.json": "CODEX_AUTH_JSON",
    "agent-usage.key": "II_OS_AGENT_USAGE_API_KEY",
}
WORKER_SOURCE_DIRECTORY = "scripts/agent/worker"
SOURCES = {
    "agent-work-ticket-core.sh": "agent-work-ticket-core.sh",
    "agent-work-ticket-status.sh": "agent-work-ticket-status.sh",
    "agent-work-ticket-prepare.sh": "agent-work-ticket-prepare.sh",
    "agent-work-ticket-execute.sh": "agent-work-ticket-execute.sh",
    "agent-workspace-materialize.py": "agent_workspace_materialize.py",
    "report-codex-exec-usage.mjs": "report-codex-exec-usage.mjs",
}
PROMPT_NAME = "ticket-prompt.json"
OWNER_NAME = ".ii-os-disposable-owner.json"
OWNER = "ii-os-agent-task"
SUBSCRIPTION_OAUTH_ERROR = (
    "CODEX_AUTH_JSON must be a subscription OAuth credential; "
    "API keys are not accepted"
)
_RUN = re.compile(r"^[0-9]+$")
_CHILD = re.compile(r"^[0-9]+-[0-9]+$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_USAGE_KEY = re.compile(
    rb"iiosu_v1\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    rb"[0-9a-f]{4}-[0-9a-f]{12}\.[A-Za-z0-9_-]{43}"
)
_PHASES = {"intent", "bound", "ready", "cleaning", "empty"}
_STALE_AFTER = 3 * 60 * 60
_MAX_PROMPT = 64 * 1024
_MAX_SOURCE = 256 * 1024


def main():
    operations = {"stage", "cleanup", "recover", "recover-all"}
    if len(sys.argv) != 2 or sys.argv[1] not in operations:
        raise SystemExit(
            "usage: agent_credential_handoff.py "
            "stage|cleanup|recover|recover-all"
        )
    os.umask(0o077)
    try:
        _run(sys.argv[1], os.environ)
    except (RuntimeError, OSError, ValueError) as error:
        raise SystemExit(f"agent_credential_handoff: {error}") from None


def _run(operation, environment):
    base, stage_root, ledger_root = handoff_roots(environment)
    for path in (base, stage_root, ledger_root):
        os.makedirs(path, mode=0o700, exist_ok=True)
    base_fd = _open_private_directory(base)
    os.close(base_fd)
    root_fd = _open_private_directory(stage_root)
    try:
        ledger_fd = _open_private_directory(ledger_root)
        try:
            if operation in {"recover", "recover-all"}:
                _recover_stale(
                    root_fd, ledger_fd, force=operation == "recover-all"
                )
                return
            run_id, attempt = _run_identity(environment)
            child = f"{run_id}-{attempt}"
            if operation == "stage":
                _recover_stale(root_fd, ledger_fd, force=False)
                _stage(
                    root_fd, ledger_fd, child, run_id, attempt,
                    stage_root=stage_root, environment=environment,
                )
            else:
                _cleanup(
                    root_fd, ledger_fd, child, run_id, attempt,
                    stage_root=stage_root, environment=environment,
                )
        finally:
            os.close(ledger_fd)
    finally:
        os.close(root_fd)


def handoff_roots(environment):
    """Return the job-scoped (base, stage, ledger) directories."""
    runner_temp = environment.get("RUNNER_TEMP", "")
    if (
        not runner_temp
        or not os.path.isabs(runner_temp)
        or "\n" in runner_temp
        or "\r" in runner_temp
    ):
        raise RuntimeError("RUNNER_TEMP must be set to an absolute path")
    # Exported paths are canonical so consumers can compare them exactly.
    base = os.path.join(os.path.realpath(runner_temp), HANDOFF_DIRECTORY)
    return base, os.path.join(base, "stage"), os.path.join(base, "ledger")


def require_subscription_oauth(value):
    """Accept only a Codex subscription OAuth credential, never an API key."""
    try:
        credential = json.loads(value)
    except (UnicodeDecodeError, ValueError):
        raise RuntimeError(SUBSCRIPTION_OAUTH_ERROR) from None
    tokens = credential.get("tokens") if isinstance(credential, dict) else None
    if (
        not isinstance(tokens, dict)
        or credential.get("OPENAI_API_KEY") not in (None, "")
        or any(
            not isinstance(tokens.get(name), str) or not tokens[name]
            for name in ("access_token", "refresh_token")
        )
    ):
        raise RuntimeError(SUBSCRIPTION_OAUTH_ERROR)


def _run_identity(environment):
    run_id = environment.get("GITHUB_RUN_ID", "")
    attempt = environment.get("GITHUB_RUN_ATTEMPT", "")
    if not _RUN.fullmatch(run_id) or not _RUN.fullmatch(attempt):
        raise RuntimeError(
            "GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT must be decimal run identity"
        )
    return run_id, attempt


def _job_identity(environment, run_id, attempt):
    repository_id = environment.get("GITHUB_REPOSITORY_ID", "")
    if not _RUN.fullmatch(repository_id):
        raise RuntimeError("GITHUB_REPOSITORY_ID must be a decimal identity")
    expected = f"github:{repository_id}:{run_id}:{attempt}:work-ticket"
    if environment.get("II_OS_AGENT_JOB_ID", "") != expected:
        raise RuntimeError(
            "II_OS_AGENT_JOB_ID does not identify this run attempt"
        )
    return expected


def _staged_values(environment):
    """Read and validate every staged value before any filesystem effect."""
    values = {}
    for name, variable in FILES.items():
        value = environment.get(variable, "").encode()
        if not value:
            raise RuntimeError(f"{variable} is missing")
        values[name] = value
    if not _USAGE_KEY.fullmatch(values["agent-usage.key"]):
        raise RuntimeError("II_OS_AGENT_USAGE_API_KEY has an invalid format")
    require_subscription_oauth(values["codex-auth.json"])
    expected_codex = environment.get("CODEX_SECRET_DIGEST", "")
    if (
        not _DIGEST.fullmatch(expected_codex)
        or hashlib.sha256(values["codex-auth.json"]).hexdigest()
        != expected_codex
    ):
        raise RuntimeError(
            "repository Codex secret changed after live verification"
        )
    try:
        prompt = base64.b64decode(
            environment.get("IIAUTO_TICKET_PROMPT_B64", ""), validate=True
        )
        prompt_object = json.loads(prompt) if prompt else None
    except (ValueError, UnicodeDecodeError):
        prompt_object = None
    prompt_digest = environment.get("IIAUTO_TICKET_PROMPT_SHA256", "")
    if (
        not isinstance(prompt_object, dict)
        or len(prompt) > _MAX_PROMPT
        or not _DIGEST.fullmatch(prompt_digest)
        or hashlib.sha256(prompt).hexdigest() != prompt_digest
    ):
        raise RuntimeError("approved ticket prompt is invalid")
    values[PROMPT_NAME] = prompt
    for name, source in SOURCES.items():
        values[name] = _read_trusted_source(
            f"{WORKER_SOURCE_DIRECTORY}/{source}"
        )
    return values


def _stage(
    root_fd, ledger_fd, child, run_id, attempt, *, stage_root, environment
):
    if not environment.get("GITHUB_ENV", ""):
        raise RuntimeError("GITHUB_ENV is required")
    job_id = _job_identity(environment, run_id, attempt)
    values = _staged_values(environment)
    digests = {
        name: hashlib.sha256(value).hexdigest()
        for name, value in values.items()
    }
    created = int(time.time())
    ledger = {
        "schema_version": 1,
        "owner": OWNER,
        "child": child,
        "run_id": run_id,
        "run_attempt": attempt,
        "job_id": job_id,
        "phase": "intent",
        "created_unix": created,
    }
    _write_ledger(ledger_fd, child, ledger, exclusive=True)
    child_fd = None
    try:
        os.mkdir(child, mode=0o700, dir_fd=root_fd)
        os.fsync(root_fd)
        child_fd = _open_child(root_fd, child)
        metadata = _require_private_directory(child_fd)
        ledger.update(
            phase="bound", device=metadata.st_dev, inode=metadata.st_ino
        )
        _write_ledger(ledger_fd, child, ledger)
        owner = {
            "owner": OWNER,
            "run_id": run_id,
            "run_attempt": attempt,
            "job_id": job_id,
            "device": metadata.st_dev,
            "inode": metadata.st_ino,
            "created_unix": created,
        }
        _write_exclusive(
            child_fd,
            OWNER_NAME,
            json.dumps(owner, sort_keys=True).encode() + b"\n",
        )
        for name in sorted(values):
            _write_exclusive(child_fd, name, values[name])
        os.fsync(child_fd)
        ledger.update(phase="ready", files=sorted(_allowed_names()))
        _write_ledger(ledger_fd, child, ledger)
        _append_file(
            environment,
            "GITHUB_ENV",
            {
                "II_OS_AGENT_HANDOFF_DIR": os.path.join(stage_root, child),
                "II_OS_AGENT_HANDOFF_DEVICE": str(metadata.st_dev),
                "II_OS_AGENT_HANDOFF_INODE": str(metadata.st_ino),
                "II_OS_AGENT_HANDOFF_DIGESTS": json.dumps(
                    digests, sort_keys=True, separators=(",", ":")
                ),
            },
        )
    except BaseException:
        if child_fd is not None:
            os.close(child_fd)
            child_fd = None
        _resume_cleanup(root_fd, ledger_fd, child, require_complete=False)
        raise
    finally:
        if child_fd is not None:
            os.close(child_fd)


def _cleanup(
    root_fd, ledger_fd, child, run_id, attempt, *, stage_root, environment
):
    expected = {}
    for name in (
        "II_OS_AGENT_HANDOFF_DIR",
        "II_OS_AGENT_HANDOFF_DEVICE",
        "II_OS_AGENT_HANDOFF_INODE",
        "II_OS_AGENT_JOB_ID",
        "GITHUB_OUTPUT",
    ):
        expected[name] = environment.get(name, "")
        if not expected[name]:
            raise RuntimeError(f"{name} is required for credential cleanup")
    ledger = _read_ledger(ledger_fd, child)
    if (
        ledger.get("run_id") != run_id
        or ledger.get("run_attempt") != attempt
        or ledger.get("job_id") != expected["II_OS_AGENT_JOB_ID"]
        or expected["II_OS_AGENT_HANDOFF_DIR"]
        != os.path.join(stage_root, child)
        or str(ledger.get("device")) != expected["II_OS_AGENT_HANDOFF_DEVICE"]
        or str(ledger.get("inode")) != expected["II_OS_AGENT_HANDOFF_INODE"]
    ):
        raise RuntimeError("credential cleanup ledger identity changed")
    _resume_cleanup(root_fd, ledger_fd, child, require_complete=True)
    _append_file(environment, "GITHUB_OUTPUT", {"proven": "true"})


def _resume_cleanup(root_fd, ledger_fd, child, *, require_complete):
    ledger = _read_ledger(ledger_fd, child)
    phase = ledger.get("phase")
    try:
        child_fd = _open_child(root_fd, child)
    except FileNotFoundError:
        if phase not in {"intent", "empty"}:
            raise RuntimeError(
                "credential directory disappeared before cleanup proof"
            ) from None
        os.unlink(f"{child}.json", dir_fd=ledger_fd)
        os.fsync(ledger_fd)
        return
    try:
        metadata = _require_private_directory(child_fd)
        if phase == "intent":
            if os.listdir(child_fd):
                raise RuntimeError(
                    "unbound credential directory is unexpectedly non-empty"
                )
            ledger.update(
                phase="empty", device=metadata.st_dev, inode=metadata.st_ino
            )
            _write_ledger(ledger_fd, child, ledger)
        else:
            if (
                metadata.st_dev != ledger.get("device")
                or metadata.st_ino != ledger.get("inode")
            ):
                raise RuntimeError("credential directory inode changed")
            names = os.listdir(child_fd)
            allowed = _allowed_names()
            if any(name not in allowed for name in names):
                raise RuntimeError(
                    "credential handoff contains an unexpected file"
                )
            if require_complete and phase == "ready" and set(names) != allowed:
                raise RuntimeError("credential handoff contents changed")
            if phase != "empty":
                ledger["phase"] = "cleaning"
                _write_ledger(ledger_fd, child, ledger)
                for name in names:
                    entry = os.stat(name, dir_fd=child_fd, follow_symlinks=False)
                    if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1:
                        raise RuntimeError(
                            "credential handoff contains an unsafe file"
                        )
                    os.unlink(name, dir_fd=child_fd)
                os.fsync(child_fd)
                ledger["phase"] = "empty"
                _write_ledger(ledger_fd, child, ledger)
        if os.listdir(child_fd):
            raise RuntimeError("credential directory did not become empty")
    finally:
        os.close(child_fd)
    os.rmdir(child, dir_fd=root_fd)
    os.fsync(root_fd)
    os.unlink(f"{child}.json", dir_fd=ledger_fd)
    os.fsync(ledger_fd)


def _recover_stale(root_fd, ledger_fd, *, force):
    now = int(time.time())
    for name in os.listdir(ledger_fd):
        if not name.endswith(".json") or not _CHILD.fullmatch(name[:-5]):
            raise RuntimeError("credential cleanup ledger has an unsafe entry")
        ledger = _read_ledger(ledger_fd, name[:-5])
        age = now - int(ledger.get("created_unix", now))
        if force or age >= _STALE_AFTER:
            _resume_cleanup(root_fd, ledger_fd, name[:-5], require_complete=False)


def _allowed_names():
    return {OWNER_NAME, PROMPT_NAME, *FILES, *SOURCES}


def _write_ledger(ledger_fd, child, value, *, exclusive=False):
    name = f"{child}.json"
    encoded = json.dumps(value, sort_keys=True).encode() + b"\n"
    if exclusive:
        _write_exclusive(ledger_fd, name, encoded)
        os.fsync(ledger_fd)
        return
    temporary = f".{child}.{os.getpid()}.{time.time_ns()}.tmp"
    _write_exclusive(ledger_fd, temporary, encoded)
    os.rename(temporary, name, src_dir_fd=ledger_fd, dst_dir_fd=ledger_fd)
    os.fsync(ledger_fd)


def _read_ledger(ledger_fd, child):
    if not _CHILD.fullmatch(child):
        raise RuntimeError("credential cleanup ledger name is invalid")
    value = json.loads(_read_regular_bytes(ledger_fd, f"{child}.json", 8192))
    if (
        not isinstance(value, dict)
        or value.get("schema_version") != 1
        or value.get("owner") != OWNER
        or value.get("child") != child
        or value.get("phase") not in _PHASES
    ):
        raise RuntimeError("credential cleanup ledger is invalid")
    return value


def _write_exclusive(directory_fd, name, value):
    descriptor = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
        0o600,
        dir_fd=directory_fd,
    )
    try:
        offset = 0
        while offset < len(value):
            written = os.write(descriptor, value[offset:])
            if written <= 0:
                raise RuntimeError("credential handoff write stopped early")
            offset += written
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _read_regular_bytes(directory_fd, name, maximum):
    descriptor = os.open(
        name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=directory_fd
    )
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
            or metadata.st_size > maximum
        ):
            raise RuntimeError("credential ledger file is invalid")
        value = os.read(descriptor, maximum + 1)
        if len(value) != metadata.st_size:
            raise RuntimeError("credential ledger file changed while reading")
        return value
    finally:
        os.close(descriptor)


def _read_trusted_source(path):
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        raise RuntimeError(f"reviewed worker source is missing: {path}") from None
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
            or metadata.st_size <= 0
            or metadata.st_size > _MAX_SOURCE
        ):
            raise RuntimeError(f"reviewed worker source is invalid: {path}")
        value = os.read(descriptor, _MAX_SOURCE + 1)
        if len(value) != metadata.st_size:
            raise RuntimeError(
                f"reviewed worker source changed while staging: {path}"
            )
        return value
    finally:
        os.close(descriptor)


def _open_private_directory(path):
    descriptor = os.open(
        path, os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        _require_private_directory(descriptor)
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def _open_child(root_fd, child):
    return os.open(
        child,
        os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
        dir_fd=root_fd,
    )


def _require_private_directory(descriptor):
    metadata = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        raise RuntimeError("credential handoff directory is not private")
    return metadata


def _append_file(environment, variable, values):
    path = environment.get(variable, "")
    if not path:
        raise RuntimeError(f"{variable} is required")
    lines = []
    for name, value in values.items():
        if "\n" in value or "\r" in value:
            raise RuntimeError(f"{name} cannot be exported on one line")
        lines.append(f"{name}={value}\n")
    with open(path, "a", encoding="utf-8") as output:
        output.write("".join(lines))


if __name__ == "__main__":
    main()
