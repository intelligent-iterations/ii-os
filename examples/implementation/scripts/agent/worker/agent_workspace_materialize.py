#!/usr/bin/env python3
"""Materialize guest changes into a fresh trusted Git repository.

The result policy of the work-ticket worker runs this file with the worker's
/usr/bin/python3 (stdlib only), fed from the reviewed source on stdin:

  note SOURCE
      Print SOURCE/.auto-agent-result.md: a bounded (12000 bytes) regular,
      single-link file opened without following links; empty when absent.

  commit SOURCE START_SHA BRANCH BUNDLE NAME EMAIL MESSAGE
      Copy only the files Git lists for SOURCE (tracked plus untracked, not
      ignored) into a fresh repository checked out at START_SHA, without
      running hooks or reading global Git configuration. Links, special files
      and multiply-linked files in the guest output are refused; symlinks and
      submodules tracked at START_SHA are restored from START_SHA. With a
      change, commit it as NAME <EMAIL> on BRANCH (ii-os-agent/<32 hex>) and
      write a verified Git bundle of BRANCH ^START_SHA to BUNDLE (absolute,
      must not exist, at most 64 MiB, mode 0600). Print one JSON object:
      {"changed_files":[...],"copied_bytes":N,"copied_files":N,"head_sha":"<40 hex>"}.
"""

from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import fcntl
from pathlib import Path


_SHA = re.compile(r"^[0-9a-f]{40}$")
_BRANCH = re.compile(r"^ii-os-agent/[0-9a-f]{32}$")
_MAX_FILES = 20000
_MAX_BYTES = 512 * 1024 * 1024


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: agent_workspace_materialize.py note|commit ...")
    if sys.argv[1] == "note" and len(sys.argv) == 3:
        sys.stdout.buffer.write(_read_note(Path(sys.argv[2])))
        return
    if sys.argv[1] != "commit" or len(sys.argv) != 9:
        raise SystemExit(
            "usage: agent_workspace_materialize.py commit "
            "SOURCE START_SHA BRANCH BUNDLE NAME EMAIL MESSAGE"
        )
    result = materialize_commit(
        source=Path(sys.argv[2]),
        start_sha=sys.argv[3],
        branch=sys.argv[4],
        bundle=Path(sys.argv[5]),
        name=sys.argv[6],
        email=sys.argv[7],
        message=sys.argv[8],
    )
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))


def materialize_commit(
    *,
    source: Path,
    start_sha: str,
    branch: str,
    bundle: Path,
    name: str,
    email: str,
    message: str,
) -> dict[str, object]:
    if (
        not source.is_absolute()
        or not bundle.is_absolute()
        or not _SHA.fullmatch(start_sha)
        or not _BRANCH.fullmatch(branch)
        or not name
        or "\n" in name
        or not email
        or "\n" in email
        or not message
        or "\n" in message
    ):
        raise RuntimeError("trusted materialization inputs are invalid")
    source_fd = os.open(
        source,
        os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
    )
    git_fd = None
    try:
        git_fd = os.open(
            ".git",
            os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=source_fd,
        )
        target = Path(
            tempfile.mkdtemp(
                prefix="ii-os-agent-trusted-",
                dir=str(source.parent),
            )
        )
        os.chmod(target, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- owner-only private directory
        home = Path(
            tempfile.mkdtemp(
                prefix="ii-os-agent-git-home-",
                dir=str(source.parent),
            )
        )
        os.chmod(home, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- owner-only private directory
        env = _git_env(home)
        git_descriptor_path = _descriptor_path(git_fd)
        if _git(
            source.parent,
            f"--git-dir={git_descriptor_path}",
            "rev-parse",
            "HEAD",
            env=env,
            pass_fds=(git_fd,),
        ).stdout.strip() != start_sha:
            raise RuntimeError("guest Git metadata changed after sandbox entry")
        _git(target, "init", "-q", env=env)
        _git(
            target,
            "fetch",
            "--no-tags",
            git_descriptor_path,
            start_sha,
            env=env,
            pass_fds=(git_fd,),
        )
        _git(target, "checkout", "-q", "-b", branch, "FETCH_HEAD", env=env)
        copy_paths = _repository_copy_paths(
            target,
            source_fd,
            env=env,
        )
        preserved_base_paths = {
            tuple(path.split("/"))
            for mode, path in _tracked_entries(
                target, start_sha, env=env
            )
            if mode in {"120000", "160000"}
        }
        _git(
            target,
            "rm",
            "-q",
            "-r",
            "-f",
            "--ignore-unmatch",
            ".",
            env=env,
        )
        target_fd = os.open(
            target,
            os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            copied = _copy_tree(
                source_fd,
                target_fd,
                excluded_paths=preserved_base_paths,
                included_paths=copy_paths,
            )
            os.fsync(target_fd)
        finally:
            os.close(target_fd)
        if preserved_base_paths:
            _git(
                target,
                "checkout",
                start_sha,
                "--",
                *("/".join(parts) for parts in sorted(preserved_base_paths)),
                env=env,
            )
        _git(target, "add", "-A", env=env)
        changed = [
            value
            for value in _git(
                target,
                "diff",
                "--cached",
                "--name-only",
                "-z",
                env=env,
            ).stdout.split("\0")
            if value
        ]
        if not changed:
            return {
                "head_sha": start_sha,
                "changed_files": [],
                "copied_files": copied[0],
                "copied_bytes": copied[1],
            }
        commit_env = {
            **env,
            "GIT_AUTHOR_NAME": name,
            "GIT_AUTHOR_EMAIL": email,
            "GIT_COMMITTER_NAME": name,
            "GIT_COMMITTER_EMAIL": email,
        }
        _git(target, "commit", "-q", "-m", message, env=commit_env)
        head_sha = _git(target, "rev-parse", "HEAD", env=env).stdout.strip()
        if not _SHA.fullmatch(head_sha):
            raise RuntimeError("trusted materialization produced an invalid commit")
        bundle.parent.mkdir(parents=True, exist_ok=True)
        if bundle.exists() or bundle.is_symlink():
            raise RuntimeError("change bundle destination already exists")
        _git(
            target,
            "bundle",
            "create",
            str(bundle),
            f"refs/heads/{branch}",
            f"^{start_sha}",
            env=env,
        )
        metadata = bundle.lstat()
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or metadata.st_size <= 0
            or metadata.st_size > 64 * 1024 * 1024
        ):
            raise RuntimeError("trusted change bundle is invalid")
        os.chmod(bundle, 0o600)
        _git(target, "bundle", "verify", str(bundle), env=env)
        return {
            "head_sha": head_sha,
            "changed_files": changed,
            "copied_files": copied[0],
            "copied_bytes": copied[1],
        }
    finally:
        if git_fd is not None:
            os.close(git_fd)
        os.close(source_fd)


def _read_note(source: Path) -> bytes:
    root_fd = os.open(
        source,
        os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
    )
    try:
        try:
            descriptor = os.open(
                ".auto-agent-result.md",
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=root_fd,
            )
        except FileNotFoundError:
            return b""
        try:
            before = os.fstat(descriptor)
            if (
                not stat.S_ISREG(before.st_mode)
                or before.st_nlink != 1
                or before.st_size > 12000
            ):
                raise RuntimeError("agent result note is not a bounded regular file")
            value = os.read(descriptor, 12001)
            after = os.fstat(descriptor)
            if (
                len(value) != before.st_size
                or (before.st_dev, before.st_ino, before.st_mtime_ns)
                != (after.st_dev, after.st_ino, after.st_mtime_ns)
            ):
                raise RuntimeError("agent result note changed while reading")
            return value
        finally:
            os.close(descriptor)
    finally:
        os.close(root_fd)


def _copy_tree(
    source_fd: int,
    target_fd: int,
    *,
    excluded_paths=None,
    included_paths=None,
) -> tuple[int, int]:
    totals = [0, 0]
    excluded = excluded_paths or set()
    included = included_paths or set()
    included_directories = {
        path[:index]
        for path in included
        for index in range(1, len(path))
    }

    def visit(
        src_fd: int,
        dst_fd: int,
        *,
        root: bool,
        parts: tuple[str, ...],
    ) -> None:
        directory_before = os.fstat(src_fd)
        names = sorted(os.listdir(src_fd))
        for name in names:
            current_parts = (*parts, name)
            if current_parts in excluded:
                continue
            if (
                current_parts not in included
                and current_parts not in included_directories
            ):
                continue
            if (
                name in {".", ".."}
                or "/" in name
                or "\0" in name
                or any(ord(character) < 32 for character in name)
            ):
                raise RuntimeError("guest workspace contains an unsafe name")
            if root and name in {".git", ".auto-agent-result.md"}:
                continue
            metadata = os.stat(name, dir_fd=src_fd, follow_symlinks=False)
            if stat.S_ISDIR(metadata.st_mode):
                if current_parts not in included_directories:
                    continue
                try:
                    os.mkdir(name, mode=0o700, dir_fd=dst_fd)
                except FileExistsError:
                    existing = os.stat(
                        name,
                        dir_fd=dst_fd,
                        follow_symlinks=False,
                    )
                    if not stat.S_ISDIR(existing.st_mode):
                        raise RuntimeError(
                            "trusted target contains an unsafe path"
                        )
                next_src = os.open(
                    name,
                    os.O_RDONLY
                    | os.O_DIRECTORY
                    | getattr(os, "O_NOFOLLOW", 0),
                    dir_fd=src_fd,
                )
                next_dst = os.open(
                    name,
                    os.O_RDONLY
                    | os.O_DIRECTORY
                    | getattr(os, "O_NOFOLLOW", 0),
                    dir_fd=dst_fd,
                )
                try:
                    opened = os.fstat(next_src)
                    if (
                        opened.st_dev,
                        opened.st_ino,
                        opened.st_mode,
                    ) != (
                        metadata.st_dev,
                        metadata.st_ino,
                        metadata.st_mode,
                    ):
                        raise RuntimeError(
                            "guest directory changed before trusted copy"
                        )
                    visit(
                        next_src,
                        next_dst,
                        root=False,
                        parts=current_parts,
                    )
                    os.fsync(next_dst)
                finally:
                    os.close(next_dst)
                    os.close(next_src)
                continue
            if current_parts not in included:
                continue
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or metadata.st_size < 0
            ):
                raise RuntimeError("guest workspace contains a link or special file")
            totals[0] += 1
            totals[1] += metadata.st_size
            if totals[0] > _MAX_FILES or totals[1] > _MAX_BYTES:
                raise RuntimeError("guest workspace exceeds trusted copy bounds")
            source_file = os.open(
                name,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=src_fd,
            )
            target_file = os.open(
                name,
                os.O_WRONLY
                | os.O_CREAT
                | os.O_EXCL
                | getattr(os, "O_NOFOLLOW", 0),
                0o755 if metadata.st_mode & 0o111 else 0o644,
                dir_fd=dst_fd,
            )
            try:
                before = os.fstat(source_file)
                if (
                    before.st_dev,
                    before.st_ino,
                    before.st_mode,
                    before.st_size,
                    before.st_mtime_ns,
                ) != (
                    metadata.st_dev,
                    metadata.st_ino,
                    metadata.st_mode,
                    metadata.st_size,
                    metadata.st_mtime_ns,
                ):
                    raise RuntimeError(
                        "guest file changed before trusted copy"
                    )
                remaining = before.st_size
                while remaining:
                    chunk = os.read(source_file, min(65536, remaining))
                    if not chunk:
                        raise RuntimeError("guest file truncated during copy")
                    _write_all(target_file, chunk)
                    remaining -= len(chunk)
                os.fsync(target_file)
                after = os.fstat(source_file)
                if (
                    before.st_dev,
                    before.st_ino,
                    before.st_size,
                    before.st_mtime_ns,
                ) != (
                    after.st_dev,
                    after.st_ino,
                    after.st_size,
                    after.st_mtime_ns,
                ):
                    raise RuntimeError("guest file changed during trusted copy")
            finally:
                os.close(target_file)
                os.close(source_file)
        directory_after = os.fstat(src_fd)
        if (
            directory_before.st_dev,
            directory_before.st_ino,
            directory_before.st_mtime_ns,
            names,
        ) != (
            directory_after.st_dev,
            directory_after.st_ino,
            directory_after.st_mtime_ns,
            sorted(os.listdir(src_fd)),
        ):
            raise RuntimeError("guest directory changed during trusted copy")

    visit(source_fd, target_fd, root=True, parts=())
    return totals[0], totals[1]


def _repository_copy_paths(
    repository: Path,
    source_fd: int,
    *,
    env: dict[str, str],
) -> set[tuple[str, ...]]:
    source_path = _descriptor_path(source_fd)
    output = _git(
        repository,
        f"--work-tree={source_path}",
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
        env=env,
        pass_fds=(source_fd,),
    ).stdout
    paths = set()
    for encoded in output.split("\0"):
        if not encoded:
            continue
        parts = tuple(encoded.split("/"))
        if (
            encoded.startswith("/")
            or any(
                not part
                or part in {".", ".."}
                or any(ord(character) < 32 for character in part)
                for part in parts
            )
        ):
            raise RuntimeError("trusted Git returned an unsafe workspace path")
        paths.add(parts)
    return paths


def _tracked_entries(
    repository: Path,
    commit: str,
    *,
    env: dict[str, str],
) -> list[tuple[str, str]]:
    output = _git(
        repository,
        "ls-tree",
        "-r",
        "-z",
        commit,
        env=env,
    ).stdout
    entries = []
    for encoded in output.split("\0"):
        if not encoded:
            continue
        metadata, separator, path = encoded.partition("\t")
        fields = metadata.split()
        if not separator or len(fields) != 3 or not path:
            raise RuntimeError("trusted Git tree is invalid")
        entries.append((fields[0], path))
    return entries


def _write_all(descriptor: int, value: bytes) -> None:
    offset = 0
    while offset < len(value):
        written = os.write(descriptor, value[offset:])
        if written <= 0:
            raise RuntimeError("trusted workspace copy stopped early")
        offset += written


def _git(
    directory: Path,
    *arguments: str,
    env: dict[str, str] | None = None,
    pass_fds: tuple[int, ...] = (),
) -> subprocess.CompletedProcess[str]:
    if env is None:
        raise RuntimeError("trusted Git environment is required")
    completed = subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", *arguments],
        cwd=directory,
        env=env,
        pass_fds=pass_fds,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    if completed.returncode:
        detail = completed.stderr.strip().replace("\n", " ")[:500]
        raise RuntimeError(f"trusted Git failed: {detail}")
    return completed


def _descriptor_path(descriptor: int) -> str:
    proc_path = f"/proc/self/fd/{descriptor}"
    if os.path.exists(proc_path):
        return proc_path
    if sys.platform == "darwin":
        raw = fcntl.fcntl(descriptor, 50, b"\0" * 1024)
        value = raw.split(b"\0", 1)[0].decode()
        if value and os.path.isabs(value):
            return value
    raise RuntimeError("descriptor-relative Git access is unavailable")


def _git_env(home: Path) -> dict[str, str]:
    return {
        "PATH": os.environ.get("PATH", ""),
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_ATTR_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ALLOW_PROTOCOL": "file",
    }


if __name__ == "__main__":
    main()
