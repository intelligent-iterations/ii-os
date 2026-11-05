"""The explicitly bound runtime host this job runs on.

ii-os never infers where an agent runs. The workflow names its runner with
II_OS_AGENT_RUNS_ON, and this module refuses to continue unless that runner
declares the host identity in II_OS_AGENT_HOST_ID and carries the reviewed
controller toolchain. The trusted controller then runs as an ordinary child
process of this job: it uses the host's own Docker Engine and firewall, the
way the public agent runtime expects of the destination's ephemeral runner.
It is never a long-lived container holding the host's Docker socket.

A kernel lock held by both this provider and its controller for their whole
lives is the absence proof a later cleanup observer relies on: the lock can
only be acquired after every process of the earlier attempt has exited.
"""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import tempfile
import threading
import time
import uuid


HOST_ID_FILE = Path("/etc/ii-os/agent-host-id")
CONTROLLER_FILE = Path("/opt/ii-os/agent-controller.json")
EXECUTION_DIR = Path("/opt/ii-os/agent_execution")
WORKSPACE = Path("/workspace")
NODE = "/usr/local/bin/node"
CODEX = "/usr/local/bin/codex"
EXECUTABLE_PATH = "/usr/local/bin:/usr/bin:/bin"
MAX_OUTPUT = 2 * 1024 * 1024
SHA = re.compile(r"[a-f0-9]{40}")
OWNER = re.compile(r"[a-f0-9]{64}")
DAEMON = re.compile(r"[A-Za-z0-9:-]{8,256}")
HOST = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
PURPOSES = {"work-ticket", "codex-auth", "codex-auth-verify", "permission-installer"}


class HostBindingError(RuntimeError):
    """A named, operator-actionable reason the bound host cannot run agents."""


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def digest(value):
    return "sha256:" + hashlib.sha256(canonical(value)).hexdigest()


def bounded_process(command, *, data=None, timeout=30, maximum=MAX_OUTPUT, env=None, cwd=None, pass_fds=()):
    """Bound both transport directions while the process is still running."""
    child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             env=env, cwd=cwd, pass_fds=pass_fds)
    chunks, size, offset = [], 0, 0
    deadline = time.monotonic() + timeout
    pending = data or b""
    try:
        with selectors.DefaultSelector() as selector:
            os.set_blocking(child.stdout.fileno(), False)
            selector.register(child.stdout, selectors.EVENT_READ)
            if pending:
                os.set_blocking(child.stdin.fileno(), False)
                selector.register(child.stdin, selectors.EVENT_WRITE)
            else:
                child.stdin.close()
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError("host process timed out")
                for key, _ in selector.select(min(remaining, 1)):
                    if key.fileobj is child.stdin:
                        try:
                            offset += os.write(child.stdin.fileno(), pending[offset:offset + 65536])
                        except BrokenPipeError:
                            offset = len(pending)
                        if offset == len(pending):
                            selector.unregister(child.stdin)
                            child.stdin.close()
                    else:
                        value = os.read(child.stdout.fileno(), 65536)
                        if not value:
                            selector.unregister(child.stdout)
                            child.stdout.close()
                        else:
                            size += len(value)
                            if size > maximum:
                                raise RuntimeError("host process output exceeded its bound")
                            chunks.append(value)
            code = child.wait(timeout=max(0.001, deadline - time.monotonic()))
            return code, b"".join(chunks)
    finally:
        if child.poll() is None:
            # Ask first: the controller turns SIGTERM into an orderly abort that
            # still tears down the worker and removes staged credentials.
            child.terminate()
            try:
                child.wait(timeout=60)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        for stream in [child.stdin, child.stdout]:
            if not stream.closed:
                stream.close()


def private_directory(path, *, create=True):
    path = Path(path)
    if create:
        try:
            path.mkdir(mode=0o700)
        except FileExistsError:
            pass
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise RuntimeError("provider state directory is not private to this user")
    return path


def private_bytes(path, maximum=MAX_OUTPUT):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_nlink != 1 or metadata.st_mode & 0o077 or metadata.st_size > maximum:
            raise RuntimeError("provider record is invalid")
        value = b""
        while len(value) < metadata.st_size:
            chunk = os.read(descriptor, metadata.st_size - len(value))
            if not chunk:
                break
            value += chunk
        if len(value) != metadata.st_size:
            raise RuntimeError("provider record changed while reading")
        return value
    finally:
        os.close(descriptor)


def private_json(path):
    return json.loads(private_bytes(path))


def _sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def durable(path, value):
    """Write a record once. A second write must carry the same bytes."""
    path = Path(path)
    encoded = canonical(value)
    if len(encoded) > MAX_OUTPUT:
        raise RuntimeError("provider record exceeded its bound")
    if path.is_symlink():
        raise RuntimeError("provider record was replaced")
    if path.exists():
        if private_bytes(path) != encoded:
            raise RuntimeError("provider record changed")
        return
    temporary = path.with_name("." + path.name + "." + uuid.uuid4().hex)
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        offset = 0
        while offset < len(encoded):
            offset += os.write(descriptor, encoded[offset:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.link(temporary, path)
    except FileExistsError:
        if private_bytes(path) != encoded:
            raise RuntimeError("provider record changed") from None
    finally:
        os.unlink(temporary)
    _sync_directory(path.parent)


def state_root(environment):
    value = environment.get("II_OS_AGENT_STATE_DIR", "")
    if not re.fullmatch(r"/[A-Za-z0-9._/-]+", value) or value.endswith("/") or "/../" in value + "/" or "/./" in value + "/":
        raise HostBindingError("II_OS_AGENT_STATE_DIR must be an absolute path on the agent host")
    root = Path(value)
    if os.path.realpath(root) != value:
        raise HostBindingError("II_OS_AGENT_STATE_DIR must be a canonical path without symbolic links")
    try:
        return private_directory(root)
    except FileNotFoundError:
        raise HostBindingError("II_OS_AGENT_STATE_DIR does not exist on the agent host; create it, owned by the runner user with mode 0700") from None
    except RuntimeError:
        raise HostBindingError("II_OS_AGENT_STATE_DIR must be owned by the runner user with mode 0700") from None


def owner_for(identity, purpose):
    if purpose not in PURPOSES:
        raise RuntimeError("runtime purpose is unsupported")
    return hashlib.sha256(f'github:{identity["repositoryId"]}:{identity["runId"]}:{purpose}'.encode()).hexdigest()


def execution_state(root, owner):
    if not OWNER.fullmatch(owner):
        raise RuntimeError("runtime owner is invalid")
    return private_directory(private_directory(root / "executions") / owner)


class HostSystem:
    """Real host operations. Tests replace this with a fixture."""

    def read(self, path, maximum=65536):
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > maximum or metadata.st_mode & 0o022:
                raise HostBindingError(f"{path} must be a regular file that only its owner can change")
            return os.read(descriptor, maximum + 1)
        finally:
            os.close(descriptor)

    def run(self, command, *, timeout=30, maximum=65536):
        try:
            return bounded_process(command, timeout=timeout, maximum=maximum,
                                   env={"PATH": EXECUTABLE_PATH, "HOME": tempfile.gettempdir()})
        except (OSError, RuntimeError):
            return 127, b""

    def workspace(self):
        try:
            metadata = WORKSPACE.lstat()
        except FileNotFoundError:
            raise HostBindingError("/workspace must exist on the agent host, owned by the runner user") from None
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid() or os.path.realpath(WORKSPACE) != str(WORKSPACE):
            raise HostBindingError("/workspace must be a real directory owned by the runner user")
        # Owner-only; the rule counts the owner's execute bit as permissive.
        os.chmod(WORKSPACE, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- owner-only directory mode
        repository = WORKSPACE / "repository"
        if repository.exists() and (repository.is_symlink() or not repository.is_dir() or any(repository.iterdir())):
            raise HostBindingError("/workspace/repository must be absent or empty before a run")


def _version_at_least(text, minimum):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)\s*", text)
    return bool(match) and tuple(int(part) for part in match.groups()) >= minimum


def load_host(environment, repository_root, *, system=None):
    """Prove this runner is the configured runtime target and return its binding."""
    system = system or HostSystem()
    expected = environment.get("II_OS_AGENT_HOST_ID", "")
    if not HOST.fullmatch(expected):
        raise HostBindingError("II_OS_AGENT_HOST_ID is not configured")
    try:
        declared = system.read(HOST_ID_FILE).decode().strip()
    except FileNotFoundError:
        raise HostBindingError(f"{HOST_ID_FILE} is missing: this runner is not an ii-os agent host") from None
    if declared != expected:
        raise HostBindingError("this runner declares a different agent host than II_OS_AGENT_HOST_ID")
    root = Path(repository_root)
    pin = json.loads((root / ".ii-os" / "agent-controller.json").read_text())
    binding = json.loads((root / ".ii-os" / "runtimes" / "execution-binding.json").read_text())
    if set(pin) != {"schemaVersion", "iiOsRepository", "iiOsCommit", "codexVersion"} or pin["schemaVersion"] != 1 \
            or not REPOSITORY.fullmatch(pin["iiOsRepository"]) or not SHA.fullmatch(pin["iiOsCommit"]) \
            or not re.fullmatch(r"\d+\.\d+\.\d+", pin["codexVersion"]):
        raise HostBindingError(".ii-os/agent-controller.json is invalid")
    if pin["iiOsCommit"] == "0" * 40:
        raise HostBindingError(".ii-os/agent-controller.json still holds the placeholder ii-os commit; pin the ii-os commit your controller image was built from")
    try:
        controller = json.loads(system.read(CONTROLLER_FILE))
    except FileNotFoundError:
        raise HostBindingError(f"{CONTROLLER_FILE} is missing: build the host from runners/agent-controller") from None
    if controller != {**pin, "runtimeRevision": binding.get("runtimeRevision")}:
        raise HostBindingError("the host's agent controller does not match the reviewed ii-os, runtime and Codex pins")
    code, version = system.run([NODE, "--version"])
    if code or not _version_at_least(version.decode(), (22, 16, 0)):
        raise HostBindingError("the agent host needs Node.js 22.16 or later at /usr/local/bin/node")
    code, version = system.run([CODEX, "--version"])
    if code or version.decode().strip() != "codex-cli " + pin["codexVersion"]:
        raise HostBindingError("the agent host's Codex does not match the reviewed harness version")
    code, daemon = system.run(["docker", "info", "--format", "{{json .ID}}"])
    try:
        daemon = json.loads(daemon) if not code else None
    except ValueError:
        daemon = None
    if not isinstance(daemon, str) or not DAEMON.fullmatch(daemon):
        raise HostBindingError("the runner user cannot reach the host's Docker Engine")
    code, _ = system.run(["sudo", "--non-interactive", "iptables", "-w", "10", "-S", "DOCKER-USER"])
    if code:
        raise HostBindingError("the runner user needs passwordless sudo for iptables and ip6tables (the runtime seals each worker's network)")
    code, _ = system.run(["tofu", "version"])
    if code:
        raise HostBindingError("the agent host needs OpenTofu on PATH")
    code, _ = system.run(["gh", "--version"])
    if code:
        raise HostBindingError("the agent host needs the GitHub CLI (gh) for the one-time Codex secret writer")
    system.workspace()
    return {"hostId": expected, "daemon": daemon, "executionDirectory": str(EXECUTION_DIR),
            "iiOsRepository": pin["iiOsRepository"], "iiOsCommit": pin["iiOsCommit"],
            "runtimeRevision": binding["runtimeRevision"], "codexVersion": pin["codexVersion"]}


@contextmanager
def operation_lock(state, *, wait_seconds=0):
    """Hold the deployment lock. Children inherit it; it frees only when all exit."""
    descriptor = os.open(state / ".controller.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_nlink != 1 or metadata.st_mode & 0o077:
            raise RuntimeError("controller lock ownership changed")
        deadline = time.monotonic() + wait_seconds
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("an earlier controller for this execution is still running") from None
                time.sleep(1)
        yield descriptor
    finally:
        os.close(descriptor)


def controller_name(owner, attempt):
    return "ii-os-controller-" + owner[:32] + "-" + str(attempt)


class LocalController:
    """Run one trusted controller attempt as a child of this job."""

    def __init__(self, host, state, *, scripts):
        self.host = host
        self.state = Path(state)
        self.scripts = Path(scripts)

    def _forward_signals(self, child_ref):
        def forward(signum, _frame):
            child = child_ref.get("child")
            if child is not None and child.poll() is None:
                child.send_signal(signal.SIGTERM)
        if threading.current_thread() is not threading.main_thread():
            return {}
        return {sig: signal.signal(sig, forward) for sig in (signal.SIGTERM, signal.SIGINT)}

    def run(self, request, *, entry):
        owner, attempt, operation = request["owner"], request["attempt"], request["operation"]
        if not OWNER.fullmatch(owner) or operation not in {"execute", "recover"} or type(attempt) is not int or not 1 <= attempt <= 100:
            raise RuntimeError("controller request is invalid")
        if operation == "execute" and attempt != 1:
            raise RuntimeError("only the first observer may launch")
        intent_file = self.state / "deployment.json"
        intent = {"schemaVersion": 1, "owner": owner, "purpose": request["purpose"], "host": self.host["hostId"],
                  "daemon": self.host["daemon"], "inputDigest": request["inputDigest"], "timeoutSeconds": request["timeoutSeconds"]}
        with operation_lock(self.state, wait_seconds=0 if operation == "execute" else 120) as lock:
            if operation == "recover" and not intent_file.exists():
                return self._never_started(request, intent)
            if operation == "execute" and intent_file.exists():
                raise RuntimeError("deployment intent already exists; recover the original execution")
            durable(intent_file, intent)
            original_file = self.state / "controller-1.json"
            original = private_json(original_file) if original_file.exists() else None
            if original is not None and (original.get("daemon") != self.host["daemon"]):
                raise RuntimeError("recovery runs on a different Docker Engine than the original execution")
            controller_id = hashlib.sha256(f"{owner}:{attempt}:{uuid.uuid4()}".encode()).hexdigest()
            durable(self.state / f"controller-{attempt}.json",
                    {"id": controller_id, "daemon": self.host["daemon"], "name": controller_name(owner, attempt)})
            envelope = request["envelope"]
            settings = envelope["settings"]
            settings["controller"] = {"id": controller_id, "daemon": self.host["daemon"], "owner": owner, "inputDigest": request["inputDigest"]}
            settings["controllerAttempt"] = attempt
            settings["mode"] = operation
            if operation == "recover":
                # The lock above proves every earlier controller exited.
                settings["previousControllersAbsent"] = {
                    "confirmed": True, "owner": owner, "daemon": self.host["daemon"], "deploymentInputDigest": request["inputDigest"],
                    "originalController": {"id": original["id"], "name": original["name"]} if original else None}
            data = canonical(envelope)
            if len(data) > 4194304:
                raise RuntimeError("controller input exceeded its bound")
            controller_state = private_directory(self.state / "controller")
            admission = private_directory(Path(request["admissionDirectory"]))
            # A short real path: native Codex binds Unix sockets beneath it.
            scratch = Path(os.path.realpath(tempfile.mkdtemp(prefix="ii-os-")))
            marker = uuid.uuid4().hex
            (scratch / ".owner").write_text(marker)
            os.chmod(scratch / ".owner", 0o600)
            env = {"PATH": EXECUTABLE_PATH, "HOME": str(scratch), "TMPDIR": str(scratch), "PYTHONDONTWRITEBYTECODE": "1",
                   "II_OS_AGENT_EXECUTION_DIR": self.host["executionDirectory"],
                   "II_OS_CONTROLLER_STATE_DIR": str(controller_state), "II_OS_CONTROLLER_ADMISSION_DIR": str(admission),
                   "II_OS_CONTROLLER_SCRATCH_DIR": str(scratch)}
            child_ref = {}
            previous = self._forward_signals(child_ref)
            try:
                timeout = min(request["timeoutSeconds"], 900) if operation == "recover" else request["timeoutSeconds"]
                code, output = self._spawn(child_ref, [NODE, str(self.scripts / entry)], data=data, env=env,
                                           cwd=str(scratch), timeout=timeout, lock=lock)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
                self._remove_scratch(scratch, marker)
            if not output.strip():
                # The controller retains its sanitized receipt before stdout.
                output = private_bytes(controller_state / f"controller-attempt-{attempt}.json")
            outcome = json.loads(output)
            durable(self.state / f"outcome-{attempt}.json", outcome)
            return {"schemaVersion": 1, "owner": owner, "daemon": self.host["daemon"], "host": self.host["hostId"],
                    "controllerAbsent": True, "exitCode": code, "outcome": outcome}

    def _spawn(self, child_ref, command, *, data, env, cwd, timeout, lock):
        child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 env=env, cwd=cwd, pass_fds=(lock,))
        child_ref["child"] = child
        try:
            output, _ = child.communicate(input=data, timeout=timeout)
        except subprocess.TimeoutExpired:
            child.terminate()
            try:
                output, _ = child.communicate(timeout=120)
            except subprocess.TimeoutExpired:
                child.kill()
                output, _ = child.communicate()
        if len(output) > MAX_OUTPUT:
            raise RuntimeError("controller output exceeded its bound")
        return child.returncode, output

    def _remove_scratch(self, scratch, marker):
        # The scratch area may hold a native harness home; remove only our own.
        if scratch.is_symlink() or (scratch / ".owner").read_text() != marker:
            raise RuntimeError("controller scratch ownership changed")
        shutil.rmtree(scratch)

    def _never_started(self, request, intent):
        # No intent means no controller was ever spawned for this owner. A
        # dedicated host must also have no runtime-owned containers or volumes.
        for kind in (["ps", "--all"], ["volume", "ls"]):
            code, value = bounded_process(["docker", *kind, "--filter", "label=agent-runtime.owner", "--format", "{{.ID}}"],
                                          timeout=30, env={"PATH": EXECUTABLE_PATH, "HOME": tempfile.gettempdir()})
            if code or value.strip():
                raise RuntimeError("missing deployment intent has ambiguous runtime resources")
        proof = {"owner": request["owner"], "daemon": self.host["daemon"], "deploymentInputDigest": request["inputDigest"], "inventoriesEmpty": True}
        outcome = {"schemaVersion": 1, "status": "never-acquired", "phase": "provider-startup", "started": False,
                   "acquired": False, "deploymentInputDigest": request["inputDigest"], "provider": proof,
                   "cleanupConfirmed": True, "cleanup": [{"component": "runtime", "confirmed": True, "absent": True}]}
        receipt = {"schemaVersion": 1, "owner": request["owner"], "daemon": self.host["daemon"], "host": self.host["hostId"],
                   "controllerAbsent": True, "exitCode": 0,
                   "outcome": {"schemaVersion": 1, "execution": {"disposition": "never-acquired", "outcome": outcome},
                               "credentialCleanupConfirmed": True, "operationSucceeded": False, "outputs": {}}}
        durable(self.state / "never-started.json", {"intent": intent, "receipt": receipt})
        return receipt


def read_collection_artifact(state, reference, maximum=67108864):
    """Read one collected result file from the controller state by its digest."""
    collections = Path(state) / "controller" / "collections"
    path = reference.get("reference", "") if isinstance(reference, dict) else ""
    if os.path.realpath(path or "/") != path or not re.fullmatch(re.escape(str(collections)) + r"/collection-[A-Za-z0-9]+/(result\.json|change\.bundle|policy\.stderr)", path) \
            or not re.fullmatch(r"sha256:[a-f0-9]{64}", reference.get("digest", "")) \
            or type(reference.get("bytes")) is not int or not 0 <= reference["bytes"] <= maximum:
        raise RuntimeError("runtime collection descriptor is invalid")
    value = private_bytes(path, maximum)
    if len(value) != reference["bytes"] or "sha256:" + hashlib.sha256(value).hexdigest() != reference["digest"]:
        raise RuntimeError("runtime artifact changed after collection")
    return value
