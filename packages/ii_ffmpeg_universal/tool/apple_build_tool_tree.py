"""Descriptor-pinned filesystem hashing for Apple build inputs."""

from __future__ import annotations

import hashlib
import os
import stat
from pathlib import Path, PurePosixPath
from typing import Any


MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024 * 1024
MAX_ENTRIES = 100_000
MAX_LINK_BYTES = 4096


class TreeAttestationError(RuntimeError):
    pass


def _identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _entry_identity(directory_fd: int, name: str) -> os.stat_result:
    try:
        return os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except OSError as error:
        raise TreeAttestationError("Build input entry identity changed") from error


class PinnedDirectory:
    """Hold one no-follow directory identity while reading relative inputs."""

    def __init__(self, root: Path):
        self.root = root
        self._closed = False
        nofollow = getattr(os, "O_NOFOLLOW", 0)
        directory = getattr(os, "O_DIRECTORY", 0)
        if not nofollow or not directory:
            raise TreeAttestationError("No-follow directory traversal is unavailable")
        self._nofollow = nofollow
        self._directory = directory
        try:
            self._path_identity = os.lstat(root)
            self.fd = os.open(root, os.O_RDONLY | directory | nofollow)
        except OSError as error:
            raise TreeAttestationError("Build input root is missing or linked") from error
        self.identity = os.fstat(self.fd)
        if (
            not stat.S_ISDIR(self.identity.st_mode)
            or _identity(self._path_identity) != _identity(self.identity)
        ):
            os.close(self.fd)
            self._closed = True
            raise TreeAttestationError("Build input root identity changed")

    def __enter__(self) -> "PinnedDirectory":
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        try:
            if exc_type is None:
                self.verify()
        finally:
            self.close()

    def close(self) -> None:
        if not self._closed:
            os.close(self.fd)
            self._closed = True

    def verify(self) -> None:
        if self._closed:
            raise TreeAttestationError("Build input root descriptor is closed")
        try:
            opened = os.fstat(self.fd)
            current = os.lstat(self.root)
        except OSError as error:
            raise TreeAttestationError(
                "Build input root was replaced while hashing"
            ) from error
        if (
            _identity(opened) != _identity(self.identity)
            or _identity(current) != _identity(self._path_identity)
        ):
            raise TreeAttestationError("Build input root was replaced while hashing")

    def _parts(self, relative: str) -> tuple[str, ...]:
        parsed = PurePosixPath(relative)
        parts = parsed.parts
        if (
            not relative
            or parsed.is_absolute()
            or relative != parsed.as_posix()
            or any(part in ("", ".", "..") for part in parts)
        ):
            raise TreeAttestationError("Build input relative path is unsafe")
        return parts

    def _consume_file(
        self, relative: str, max_file_bytes: int, retain_bytes: bool
    ) -> tuple[str, bytes | None]:
        parts = self._parts(relative)
        current_fd = self.fd
        directories: list[tuple[int, str, int, os.stat_result]] = []
        file_fd: int | None = None
        try:
            for name in parts[:-1]:
                before = _entry_identity(current_fd, name)
                if not stat.S_ISDIR(before.st_mode):
                    raise TreeAttestationError("Build input directory is unsafe")
                try:
                    child_fd = os.open(
                        name,
                        os.O_RDONLY | self._directory | self._nofollow,
                        dir_fd=current_fd,
                    )
                except OSError as error:
                    raise TreeAttestationError(
                        "Build input directory identity changed"
                    ) from error
                opened = os.fstat(child_fd)
                if (
                    opened.st_dev != self.identity.st_dev
                    or _identity(opened) != _identity(before)
                ):
                    os.close(child_fd)
                    raise TreeAttestationError(
                        "Build input directory identity changed"
                    )
                directories.append((current_fd, name, child_fd, before))
                current_fd = child_fd

            leaf = parts[-1]
            before = _entry_identity(current_fd, leaf)
            try:
                file_fd = os.open(
                    leaf, os.O_RDONLY | self._nofollow, dir_fd=current_fd
                )
            except OSError as error:
                raise TreeAttestationError(
                    "Build input file is missing or linked"
                ) from error
            opened = os.fstat(file_fd)
            if (
                not stat.S_ISREG(opened.st_mode)
                or _identity(opened) != _identity(before)
                or opened.st_size <= 0
                or opened.st_size > max_file_bytes
            ):
                raise TreeAttestationError("Build input file identity is invalid")
            digest = hashlib.sha256()
            chunks: list[bytes] | None = [] if retain_bytes else None
            observed_bytes = 0
            while chunk := os.read(file_fd, 1024 * 1024):
                observed_bytes += len(chunk)
                digest.update(chunk)
                if chunks is not None:
                    chunks.append(chunk)
            if (
                observed_bytes != opened.st_size
                or _identity(os.fstat(file_fd)) != _identity(opened)
                or _identity(_entry_identity(current_fd, leaf)) != _identity(before)
            ):
                raise TreeAttestationError("Build input file changed while hashing")
            for parent_fd, name, child_fd, expected in reversed(directories):
                if (
                    _identity(os.fstat(child_fd)) != _identity(expected)
                    or _identity(_entry_identity(parent_fd, name))
                    != _identity(expected)
                ):
                    raise TreeAttestationError(
                        "Build input directory changed while hashing"
                    )
            self.verify()
            return digest.hexdigest(), b"".join(chunks) if chunks is not None else None
        finally:
            if file_fd is not None:
                os.close(file_fd)
            for _, _, child_fd, _ in reversed(directories):
                os.close(child_fd)

    def hash_file(self, relative: str, max_file_bytes: int) -> str:
        digest, _ = self._consume_file(relative, max_file_bytes, False)
        return digest

    def read_file(self, relative: str, max_file_bytes: int) -> bytes:
        _, value = self._consume_file(relative, max_file_bytes, True)
        if value is None:
            raise TreeAttestationError("Build input file could not be retained")
        return value


def hash_file_bounded(path: Path, max_file_bytes: int) -> str:
    with PinnedDirectory(path.parent) as root:
        return root.hash_file(path.name, max_file_bytes)


def read_file_bounded(path: Path, max_file_bytes: int) -> bytes:
    with PinnedDirectory(path.parent) as root:
        return root.read_file(path.name, max_file_bytes)


def attest_tree(root: Path) -> dict[str, Any]:
    return attest_tree_bounded(root)


def _safe_link(relative: str, target: str, max_link_bytes: int) -> None:
    if not target or len(target.encode()) > max_link_bytes or target.startswith("/"):
        raise TreeAttestationError("Build input link target is unsafe")
    stack = relative.split("/")[:-1]
    for part in target.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not stack:
                raise TreeAttestationError("Build input link escapes its root")
            stack.pop()
        else:
            stack.append(part)


def attest_tree_bounded(
    root: Path,
    *,
    max_file_bytes: int = MAX_FILE_BYTES,
    max_total_bytes: int = MAX_TOTAL_BYTES,
    max_entries: int = MAX_ENTRIES,
    max_link_bytes: int = MAX_LINK_BYTES,
) -> dict[str, Any]:
    """Hash a tree through descriptor-relative, no-follow reads."""
    with PinnedDirectory(root) as pinned:
        digest = hashlib.sha256()
        entry_count = 0
        file_count = 0
        link_count = 0
        total_bytes = 0

        def visit(directory_fd: int, parent: str) -> None:
            nonlocal entry_count, file_count, link_count, total_bytes
            try:
                entries = sorted(os.scandir(directory_fd), key=lambda value: value.name)
            except OSError as error:
                raise TreeAttestationError(
                    "Build input directory cannot be read"
                ) from error
            for entry in entries:
                if not entry.name or "/" in entry.name or entry.name in (".", ".."):
                    raise TreeAttestationError("Build input entry name is unsafe")
                relative = f"{parent}/{entry.name}" if parent else entry.name
                metadata = _entry_identity(directory_fd, entry.name)
                entry_count += 1
                if entry_count > max_entries:
                    raise TreeAttestationError("Build input tree has too many entries")
                mode = stat.S_IMODE(metadata.st_mode)
                if stat.S_ISDIR(metadata.st_mode):
                    digest.update(f"D\0{relative}\0{mode:o}\n".encode())
                    try:
                        child_fd = os.open(
                            entry.name,
                            os.O_RDONLY | pinned._directory | pinned._nofollow,
                            dir_fd=directory_fd,
                        )
                    except OSError as error:
                        raise TreeAttestationError(
                            "Build input directory identity changed"
                        ) from error
                    try:
                        opened = os.fstat(child_fd)
                        if (
                            opened.st_dev != pinned.identity.st_dev
                            or _identity(opened) != _identity(metadata)
                        ):
                            raise TreeAttestationError(
                                "Build input directory identity changed"
                            )
                        visit(child_fd, relative)
                        if _identity(os.fstat(child_fd)) != _identity(opened):
                            raise TreeAttestationError(
                                "Build input directory changed while hashing"
                            )
                    finally:
                        os.close(child_fd)
                    if _identity(_entry_identity(directory_fd, entry.name)) != _identity(
                        metadata
                    ):
                        raise TreeAttestationError(
                            "Build input directory was replaced while hashing"
                        )
                elif stat.S_ISLNK(metadata.st_mode):
                    try:
                        target = os.readlink(entry.name, dir_fd=directory_fd)
                    except OSError as error:
                        raise TreeAttestationError(
                            "Build input link identity changed"
                        ) from error
                    _safe_link(relative, target, max_link_bytes)
                    if _identity(_entry_identity(directory_fd, entry.name)) != _identity(
                        metadata
                    ):
                        raise TreeAttestationError(
                            "Build input link was replaced while hashing"
                        )
                    digest.update(f"L\0{relative}\0{mode:o}\0{target}\n".encode())
                    link_count += 1
                elif stat.S_ISREG(metadata.st_mode):
                    if metadata.st_size > max_file_bytes:
                        raise TreeAttestationError("Build input file is oversized")
                    total_bytes += metadata.st_size
                    if total_bytes > max_total_bytes:
                        raise TreeAttestationError("Build input tree is oversized")
                    value = hashlib.sha256()
                    observed_bytes = 0
                    try:
                        file_fd = os.open(
                            entry.name,
                            os.O_RDONLY | pinned._nofollow,
                            dir_fd=directory_fd,
                        )
                    except OSError as error:
                        raise TreeAttestationError(
                            "Build input file identity changed"
                        ) from error
                    try:
                        opened = os.fstat(file_fd)
                        if not stat.S_ISREG(opened.st_mode) or _identity(
                            opened
                        ) != _identity(metadata):
                            raise TreeAttestationError(
                                "Build input file identity changed"
                            )
                        while chunk := os.read(file_fd, 1024 * 1024):
                            observed_bytes += len(chunk)
                            value.update(chunk)
                        if _identity(os.fstat(file_fd)) != _identity(opened):
                            raise TreeAttestationError(
                                "Build input file changed while hashing"
                            )
                    finally:
                        os.close(file_fd)
                    if (
                        observed_bytes != metadata.st_size
                        or _identity(_entry_identity(directory_fd, entry.name))
                        != _identity(metadata)
                    ):
                        raise TreeAttestationError(
                            "Build input file was replaced while hashing"
                        )
                    digest.update(
                        f"F\0{relative}\0{mode:o}\0{metadata.st_size}\0"
                        f"{value.hexdigest()}\n".encode()
                    )
                    file_count += 1
                else:
                    raise TreeAttestationError("Build input tree has a special file")

        visit(pinned.fd, "")
        pinned.verify()
        return {
            "entry_count": entry_count,
            "file_count": file_count,
            "link_count": link_count,
            "total_bytes": total_bytes,
            "sha256": digest.hexdigest(),
        }
