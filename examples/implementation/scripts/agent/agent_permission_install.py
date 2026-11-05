"""Install one approved runtime permission profile and its readiness proof.

Usage: agent_permission_install.py [receive]

Run from the root of a prepared checkout of the repository agents work on.
The reviewed executable sources are listed in
``.ii-os/agent-trusted-source-manifest.json`` (schema_version 1, blob_shas,
executable_paths, python_import_namespaces), the same schema the ii-os backend
uses to judge readiness.

Environment (each is required and reported by name when missing):
  PROFILE_ID, PROFILE_VERSION, PROFILE_DIGEST, PROFILE_JSON
      The approved schema 4 profile and its canonical sha256 digest.
  APPROVAL_ID, DISPATCH_ID
      The ii-os approval and dispatch this installation answers.
  GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, GITHUB_SHA
      The installer run; GITHUB_SHA is the reviewed source commit.
  PROFILE_B64, PROOF_B64 (``receive`` only)
      Previously produced files that must equal what this run produces.

Writes ``.ii-os/agent-permissions/<id>.json`` and
``.ii-os/agent-permission-proofs/<id>.json`` only after every check passes.
"""

import base64
import hashlib
import json
import os
import pathlib
import re
import stat
import subprocess
import sys

from agent_task_profile import canonical_profile_digest, validate_executable_profile


MANIFEST_PATH = ".ii-os/agent-trusted-source-manifest.json"
PROFILE_DIRECTORY = ".ii-os/agent-permissions"
PROOF_DIRECTORY = ".ii-os/agent-permission-proofs"
WORKFLOW_DIRECTORY = ".github/workflows/"
SECURITY_CONTRACT = 7
PROOF_SCHEMA_VERSION = 2
AGENT_ENVIRONMENTS = ("ii-os-agent-maintainer", "ii-os-agent-bootstrap")
MAX_WORKFLOWS = 100
MAX_MANIFEST_BYTES = 1024 * 1024
_SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_APPROVAL = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
_DISPATCH = re.compile(r"^[A-Za-z0-9_-]{20,128}$")
_BLOB = re.compile(r"^[0-9a-f]{40}$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_DECIMAL = re.compile(r"^[1-9][0-9]{0,18}$")
_MANIFEST_KEYS = {
    "schema_version",
    "blob_shas",
    "executable_paths",
    "python_import_namespaces",
}


def _required(environment, name):
    value = environment.get(name, "")
    if not value:
        raise SystemExit(f"{name} is required")
    return value


def _git(*arguments):
    completed = subprocess.run(
        ["git", "--literal-pathspecs", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=120,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().replace("\n", " ")[:300]
        raise SystemExit(f"git {arguments[0]} failed: {detail}")
    return completed.stdout


def _require_repository_root():
    top = _git("rev-parse", "--show-toplevel").strip()
    if not top or pathlib.Path(top).resolve() != pathlib.Path.cwd().resolve():
        raise SystemExit("installer must run from the repository root")


def _index_entries(*paths):
    """Return {path: (mode, blob)} for stage-0 index entries under paths."""
    entries = {}
    for record in _git("ls-files", "-s", "-z", "--", *paths).split("\0"):
        if not record:
            continue
        metadata, _, name = record.partition("\t")
        fields = metadata.split()
        if len(fields) != 3 or fields[2] != "0" or not name:
            raise SystemExit(f"index entry is not a merged regular entry: {name}")
        entries[name] = (fields[0], fields[1])
    return entries


def _committed_blobs(paths):
    """Prove each path is a regular file whose bytes equal its index entry.

    Returns {path: (mode, blob)} using one index listing and one hash pass.
    """
    paths = sorted(set(paths))
    for path in paths:
        try:
            metadata = pathlib.Path(path).lstat()
        except FileNotFoundError:
            raise SystemExit(f"required source is missing: {path}") from None
        if not stat.S_ISREG(metadata.st_mode):
            raise SystemExit(f"required source is not a regular file: {path}")
    entries = _index_entries(*paths)
    blobs = _git("hash-object", "--", *paths).split()
    if len(blobs) != len(paths):
        raise SystemExit("git hash-object returned an incomplete answer")
    committed = {}
    for path, blob in zip(paths, blobs):
        entry = entries.get(path)
        if entry is None or entry[0] not in ("100644", "100755") or entry[1] != blob:
            raise SystemExit(f"source is not committed regular source: {path}")
        committed[path] = entry
    return committed


def _safe_path(path):
    """The backend's rule: relative, no backslash, no '.' or '..' segment."""
    return (
        isinstance(path, str)
        and bool(path)
        and not path.startswith("/")
        and "\\" not in path
        and ".." not in path.split("/")
        and "." not in path.split("/")
    )


def _string_list(value, label):
    if (
        not isinstance(value, list)
        or any(not isinstance(item, str) or not item for item in value)
        or len(set(value)) != len(value)
    ):
        raise SystemExit(f"trusted source manifest {label} is invalid")
    return set(value)


def validate_trusted_source_manifest(manifest):
    """Apply the backend's manifest schema; return (blob_shas, modes)."""
    if (
        not isinstance(manifest, dict)
        or set(manifest) != _MANIFEST_KEYS
        or type(manifest["schema_version"]) is not int
        or manifest["schema_version"] != 1
    ):
        raise SystemExit("trusted source manifest envelope is invalid")
    blob_shas = manifest["blob_shas"]
    if (
        not isinstance(blob_shas, dict)
        or not blob_shas
        or any(
            not _safe_path(path)
            or not isinstance(blob, str)
            or not _BLOB.fullmatch(blob)
            for path, blob in blob_shas.items()
        )
    ):
        raise SystemExit("trusted source manifest blob_shas are invalid")
    executable = _string_list(manifest["executable_paths"], "executable_paths")
    if not executable.issubset(blob_shas):
        raise SystemExit(
            "trusted source manifest executable_paths are not reviewed sources"
        )
    namespaces = manifest["python_import_namespaces"]
    if not isinstance(namespaces, dict) or any(
        not _safe_path(directory) for directory in namespaces
    ):
        raise SystemExit(
            "trusted source manifest python_import_namespaces are invalid"
        )
    namespaced = set()
    for directory, names in namespaces.items():
        for name in _string_list(names, "python_import_namespaces"):
            namespaced.add(f"{directory}/{name}")
    reviewed_python = {path for path in blob_shas if path.endswith(".py")}
    if reviewed_python != namespaced:
        raise SystemExit(
            "trusted source manifest Python namespaces must cover every "
            "reviewed Python source exactly"
        )
    modes = {
        path: "100755" if path in executable else "100644"
        for path in blob_shas
    }
    return dict(blob_shas), modes


def load_trusted_source_manifest():
    """Read the committed manifest and validate it like the backend does."""
    committed = _committed_blobs([MANIFEST_PATH])
    if committed[MANIFEST_PATH][0] != "100644":
        raise SystemExit(f"source is not committed regular source: {MANIFEST_PATH}")
    encoded = pathlib.Path(MANIFEST_PATH).read_bytes()
    if len(encoded) > MAX_MANIFEST_BYTES:
        raise SystemExit("trusted source manifest exceeds its bound")
    try:
        manifest = json.loads(encoded)
    except (ValueError, UnicodeDecodeError):
        raise SystemExit("trusted source manifest is not JSON") from None
    return validate_trusted_source_manifest(manifest)


def _validated_inputs(environment):
    values = {
        name: _required(environment, name)
        for name in (
            "PROFILE_ID",
            "APPROVAL_ID",
            "DISPATCH_ID",
            "PROFILE_JSON",
            "PROFILE_VERSION",
            "PROFILE_DIGEST",
            "GITHUB_RUN_ID",
            "GITHUB_RUN_ATTEMPT",
            "GITHUB_SHA",
        )
    }
    if (
        not _SAFE_NAME.fullmatch(values["PROFILE_ID"])
        or not _APPROVAL.fullmatch(values["APPROVAL_ID"])
        or not _DISPATCH.fullmatch(values["DISPATCH_ID"])
    ):
        raise SystemExit("invalid approval, dispatch, or profile identity")
    for name in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        if not _DECIMAL.fullmatch(values[name]):
            raise SystemExit(f"{name} must be a positive decimal")
    if not _BLOB.fullmatch(values["GITHUB_SHA"]):
        raise SystemExit("GITHUB_SHA must be a full lowercase commit SHA")
    try:
        profile = json.loads(values["PROFILE_JSON"])
    except ValueError:
        raise SystemExit("PROFILE_JSON must be one JSON profile") from None
    validate_executable_profile(profile, expected_id=values["PROFILE_ID"])
    if (
        profile.get("version") != values["PROFILE_VERSION"]
        or not _DIGEST.fullmatch(values["PROFILE_DIGEST"])
        or canonical_profile_digest(profile) != values["PROFILE_DIGEST"]
    ):
        raise SystemExit("profile version or digest mismatch")
    return values, profile


def _verify_runtime_inputs(profile):
    paths = []
    for reference in profile["runtime"].values():
        path = reference["path"]
        source = pathlib.Path(path)
        if source.is_symlink() or not source.is_file():
            raise SystemExit("approved runtime input is not a regular file")
        if hashlib.sha256(source.read_bytes()).hexdigest() != reference["sha256"]:
            raise SystemExit("approved runtime input changed before installation")
        paths.append(path)
    for path, (mode, _) in _committed_blobs(paths).items():
        if mode != "100644":
            raise SystemExit(f"source is not committed regular source: {path}")


def _workflow_paths():
    paths = sorted(
        path
        for path in _index_entries(WORKFLOW_DIRECTORY.rstrip("/"))
        if path.startswith(WORKFLOW_DIRECTORY)
        and path.endswith((".yml", ".yaml"))
    )
    if not paths or len(paths) > MAX_WORKFLOWS:
        raise SystemExit(
            f"workflow namespace is empty or exceeds {MAX_WORKFLOWS} files"
        )
    return paths


def _source_proofs(blob_shas, modes):
    """Return the trusted-source and workflow-namespace blob/mode maps."""
    workflows = _workflow_paths()
    missing = sorted(
        path for path in blob_shas
        if path.startswith(WORKFLOW_DIRECTORY) and path not in workflows
    )
    if missing:
        raise SystemExit(
            f"reviewed workflow is outside the workflow namespace: {missing[0]}"
        )
    committed = _committed_blobs([*blob_shas, *workflows])
    trusted_blobs = {}
    trusted_modes = {}
    for path in sorted(blob_shas):
        mode, blob = committed[path]
        if blob != blob_shas[path] or mode != modes[path]:
            raise SystemExit(
                f"trusted source differs from the reviewed manifest: {path}"
            )
        trusted_blobs[path] = blob
        trusted_modes[path] = mode
    workflow_blobs = {}
    workflow_modes = {}
    for path in workflows:
        mode, blob = committed[path]
        if mode != "100644":
            raise SystemExit(f"workflow is not a regular non-executable file: {path}")
        text = pathlib.Path(path).read_bytes().decode("utf-8", "replace")
        normalized = text.casefold()
        if path not in blob_shas and any(
            name in normalized for name in AGENT_ENVIRONMENTS
        ):
            raise SystemExit(
                f"unreviewed workflow selects an agent environment: {path}"
            )
        workflow_blobs[path] = blob
        workflow_modes[path] = mode
    return trusted_blobs, trusted_modes, workflow_blobs, workflow_modes


def build_installation(environment):
    """Return (profile_id, profile_bytes, proof_bytes) after every check."""
    values, profile = _validated_inputs(environment)
    _require_repository_root()
    _verify_runtime_inputs(profile)
    blob_shas, manifest_modes = load_trusted_source_manifest()
    (
        trusted_blobs,
        trusted_modes,
        workflow_blobs,
        workflow_modes,
    ) = _source_proofs(blob_shas, manifest_modes)
    proof = {
        "schema_version": PROOF_SCHEMA_VERSION,
        "security_contract": SECURITY_CONTRACT,
        "approval_id": values["APPROVAL_ID"],
        "dispatch_id": values["DISPATCH_ID"],
        "profile_id": values["PROFILE_ID"],
        "profile_version": values["PROFILE_VERSION"],
        "profile_digest": values["PROFILE_DIGEST"],
        "installer_run_id": int(values["GITHUB_RUN_ID"]),
        "installer_run_attempt": int(values["GITHUB_RUN_ATTEMPT"]),
        "installer_source_sha": values["GITHUB_SHA"],
        "trusted_source_blob_shas": trusted_blobs,
        "trusted_source_modes": trusted_modes,
        "workflow_namespace_blob_shas": workflow_blobs,
        "workflow_namespace_modes": workflow_modes,
        "runtime_configuration_sha256": (
            profile["runtime"]["configuration"]["sha256"]
        ),
        "execution_binding_sha256": (
            profile["runtime"]["execution_binding"]["sha256"]
        ),
    }
    return values["PROFILE_ID"], _encode_json(profile), _encode_json(proof)


def _encode_json(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def _destination(directory, profile_id):
    for path in (pathlib.Path(".ii-os"), pathlib.Path(directory)):
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            raise SystemExit(f"installation directory is not a directory: {path}")
    destination = pathlib.Path(directory) / f"{profile_id}.json"
    if destination.is_symlink():
        raise SystemExit(f"installation target is a symlink: {destination}")
    return destination


def main(environment=None):
    environment = os.environ if environment is None else environment
    profile_id, profile, proof = build_installation(environment)
    for directory, encoded in (
        (PROFILE_DIRECTORY, profile),
        (PROOF_DIRECTORY, proof),
    ):
        destination = _destination(directory, profile_id)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(encoded)
    return profile_id


def receive(environment=None):
    """Check delivered files against this same frozen-source verifier."""
    environment = os.environ if environment is None else environment
    delivered = {}
    for name, directory, maximum in (
        ("PROFILE_B64", PROFILE_DIRECTORY, 65536),
        ("PROOF_B64", PROOF_DIRECTORY, 1048576),
    ):
        encoded = _required(environment, name)
        if len(encoded) > maximum * 2:
            raise SystemExit("runtime permission delivery exceeds its bound")
        try:
            value = base64.b64decode(encoded, validate=True)
        except ValueError:
            raise SystemExit(f"{name} must be base64") from None
        if len(value) > maximum:
            raise SystemExit("runtime permission delivery exceeds its bound")
        delivered[directory] = value
    profile_id = main(environment)
    for directory, expected in delivered.items():
        path = pathlib.Path(directory) / f"{profile_id}.json"
        if path.read_bytes() != expected:
            raise SystemExit(
                "runtime permission delivery differs from the approved source proof"
            )


if __name__ == "__main__":
    if sys.argv[1:] == ["receive"]:
        receive()
    elif not sys.argv[1:]:
        main()
    else:
        raise SystemExit("usage: agent_permission_install.py [receive]")
