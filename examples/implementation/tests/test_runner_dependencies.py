"""Runner images install Python packages only from their hash-pinned locks.

A runner that installs Python packages ships `requirements.lock.txt` (what the
runner imports) and `requirements-build.lock.txt` (the installer), with an
exact version and a sha256 for every package. Its Dockerfile installs from
those files with `--require-hashes --no-deps`, so the image holds exactly what
the locks list, and the release dependency scan, which reads
`requirements*.txt`, checks what the image installs.
"""

from __future__ import annotations

from pathlib import Path
import re
import shlex
import unittest

from tests.support import RUNNERS

LOCKS = ("requirements-build.lock.txt", "requirements.lock.txt")
PINNED = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([^\s;\\]+) *\\?$")
DIRECT_URL = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*) @ (https://\S+) *\\?$")
HASH = re.compile(r"^ +--hash=sha256:[0-9a-f]{64}(?: \\)?$")
TORCH_CU128_INDEX = "https://download.pytorch.org/whl/cu128"
# The base image's Ubuntu release fixes the Python the image runs.
UBUNTU_PYTHON = {"ubuntu22.04": ("3.10", "x86_64-manylinux_2_35"), "ubuntu24.04": ("3.12", "x86_64-manylinux_2_39")}
# Direct-URL wheels are hash-pinned but invisible to advisory databases; each
# one is named in the runner README and docs/generation.md.
DIRECT_URL_PACKAGES = {}


def normalize(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def lock_entries(path: Path) -> dict[str, tuple[str, list[str]]]:
    """name -> (version or URL, hashes); fails on anything that is not pinned."""
    entries: dict[str, tuple[str, list[str]]] = {}
    current: str | None = None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith(" "):
            if current is None or not HASH.fullmatch(line):
                raise AssertionError(f"{path.name}:{number} is not a sha256 hash line: {line.strip()[:60]}")
            entries[current][1].append(line.strip())
            continue
        match = PINNED.fullmatch(line) or DIRECT_URL.fullmatch(line)
        if match is None:
            raise AssertionError(f"{path.name}:{number} is not an exact pin: {line[:60]}")
        current = normalize(match.group(1))
        if current in entries:
            raise AssertionError(f"{path.name} pins {current} twice")
        entries[current] = (match.group(2), [])
    return entries


def split_commands(script: str) -> list[str]:
    """Split a shell line at `&&` and `;` that are outside quotes."""
    commands, current, quote, index = [], [], "", 0
    while index < len(script):
        char = script[index]
        if quote:
            quote = "" if char == quote else quote
        elif char in "'\"":
            quote = char
        elif char == ";" or script.startswith("&&", index):
            commands.append("".join(current))
            current = []
            index += 2 if char == "&" else 1
            continue
        current.append(char)
        index += 1
    commands.append("".join(current))
    return [" ".join(command.split()) for command in commands if command.strip()]


def run_commands(dockerfile: str) -> list[tuple[int, str]]:
    """Each shell command of each RUN, with the RUN's position in the file."""
    joined = re.sub(r"\\\n", " ", dockerfile)
    commands: list[tuple[int, str]] = []
    for index, line in enumerate(joined.splitlines()):
        if line.startswith("RUN "):
            commands.extend((index, command) for command in split_commands(line[4:]))
    return commands


def installs(dockerfile: str) -> list[tuple[int, list[str]]]:
    """Every pip or `uv pip` package installation, as argument lists."""
    found = []
    for index, command in run_commands(dockerfile):
        words = shlex.split(command)
        if "install" in words and any(Path(word).name in {"pip", "pip3"} for word in words[: words.index("install")]):
            found.append((index, words))
    return found


VALUE_OPTIONS = {"--python", "--index-url", "--extra-index-url", "--index-strategy", "--only-binary", "--no-binary", "-r", "-c"}


def install_arguments(words: list[str]) -> tuple[dict[str, list[str]], list[str]]:
    """(option -> values, sources) for the words after `install`."""
    options: dict[str, list[str]] = {}
    sources: list[str] = []
    rest = iter(words[words.index("install") + 1 :])
    for word in rest:
        if word in VALUE_OPTIONS:
            options.setdefault(word, []).append(next(rest))
        elif word == "-e":
            sources.append(next(rest))
        elif word.startswith("-"):
            options.setdefault(word, [])
        else:
            sources.append(word)
    return options, sources


def python_runners() -> list[Path]:
    return sorted(path.parent for path in RUNNERS.glob("*/Dockerfile") if installs(path.read_text(encoding="utf-8")))


class RunnerDependencyLocksTest(unittest.TestCase):
    def test_updated_media_runners_do_not_restore_vulnerable_dependency_versions(self) -> None:
        # Minimum patched releases for the reviewed OSV findings. The release
        # scan remains authoritative for new advisories and transitive packages.
        floors = {"pillow": (13, 0, 0), "filelock": (4, 2, 1),
                  "torch": (2, 13, 0), "setuptools": (84, 1, 0)}
        for name in ("comfyui-image", "ltx-video", "seedvr2-video", "acestep-song", "chatterbox-narration"):
            runner = RUNNERS / name
            entries = lock_entries(runner / "requirements.lock.txt")
            for package, floor in floors.items():
                with self.subTest(runner=name, package=package):
                    version = entries[package][0].split("+", 1)[0]
                    self.assertGreaterEqual(tuple(map(int, version.split("."))), floor)
            installer = lock_entries(runner / "requirements-build.lock.txt")["pip"][0]
            self.assertGreaterEqual(tuple(map(int, installer.split("."))), (26, 2, 2))

    def test_runner_installers_do_not_restore_vulnerable_versions(self) -> None:
        for name in ("acestep-song", "open-jev"):
            entries = lock_entries(RUNNERS / name / "requirements-build.lock.txt")
            self.assertGreaterEqual(tuple(map(int, entries["pip"][0].split("."))), (26, 2, 2))
    def test_headless_audio_runners_have_no_pickle_cache_or_ui_dependency(self) -> None:
        for name in ("acestep-song", "chatterbox-narration"):
            entries = lock_entries(RUNNERS / name / "requirements.lock.txt")
            self.assertNotIn("diskcache", entries)
            self.assertNotIn("gradio", entries)
            self.assertNotIn("flash-attn", entries)
            self.assertGreaterEqual(tuple(map(int, entries["transformers"][0].split("."))), (5, 10, 1))
            self.assertGreaterEqual(tuple(map(int, entries["diffusers"][0].split("."))), (0, 38, 0))

    def test_the_python_runners_are_the_ones_that_ship_locks(self) -> None:
        with_locks = sorted(path.parent for path in RUNNERS.glob("*/requirements.lock.txt"))
        self.assertEqual([path.name for path in python_runners()], [path.name for path in with_locks])
        self.assertEqual(
            [path.name for path in with_locks],
            ["acestep-song", "chatterbox-narration", "comfyui-image", "ltx-video", "minimax-h3", "open-jev", "seedvr2-video"],
        )

    def test_every_lock_pins_each_package_once_with_hashes(self) -> None:
        for runner in python_runners():
            for name in LOCKS:
                with self.subTest(runner=runner.name, lock=name):
                    self.assertRegex(name, r"^requirements[^/]*\.txt$", "the release scan only reads requirements*.txt")
                    entries = lock_entries(runner / name)
                    self.assertTrue(entries)
                    for package, (_, hashes) in entries.items():
                        self.assertTrue(hashes, f"{package} has no sha256")
                    urls = {package for package, (pin, _) in entries.items() if pin.startswith("https://")}
                    self.assertEqual(urls, DIRECT_URL_PACKAGES.get(runner.name, set()) if name == "requirements.lock.txt" else set())

    def test_dockerfiles_install_only_from_their_locks(self) -> None:
        for runner in python_runners():
            with self.subTest(runner=runner.name):
                dockerfile = (runner / "Dockerfile").read_text(encoding="utf-8")
                for _, command in run_commands(dockerfile):
                    self.assertNotRegex(command, r"\buv (sync|add|run)\b|easy_install|--upgrade\b|\binstall -U\b")
                installed = []
                for index, words in installs(dockerfile):
                    options, sources = install_arguments(words)
                    self.assertIn("--no-deps", options)
                    self.assertNotIn("-c", options)
                    if "-r" in options:
                        self.assertIn("--require-hashes", options)
                        self.assertEqual(sources, [], "a locked install names no other package")
                        (target,) = options["-r"]
                        self.assertIn(target, [f"/opt/ii-os-runner/{runner.name}/{lock}" for lock in LOCKS])
                        installed.append((index, Path(target).name))
                    else:
                        # Only a source tree already checked out at a pinned
                        # revision may be installed without a lock, and never
                        # with its dependencies: a local path, never a name or URL.
                        self.assertTrue(sources)
                        for source in sources:
                            self.assertRegex(source, r"^(\.|/[A-Za-z0-9_.-]+)(/[A-Za-z0-9_.-]+)*$")
                self.assertEqual(sorted(lock for _, lock in installed), sorted(LOCKS))
                build_at = next(index for index, lock in installed if lock == LOCKS[0])
                runtime_at = next(index for index, lock in installed if lock == LOCKS[1])
                self.assertLessEqual(build_at, runtime_at, "the installer comes from its own lock first")
                copied = dockerfile.index(
                    f"COPY runners/{runner.name}/requirements-build.lock.txt runners/{runner.name}/requirements.lock.txt "
                    f"/opt/ii-os-runner/{runner.name}/"
                )
                self.assertLess(copied, dockerfile.index(f"-r /opt/ii-os-runner/{runner.name}/"))

    def test_locks_target_the_python_and_indexes_the_image_uses(self) -> None:
        for runner in python_runners():
            with self.subTest(runner=runner.name):
                dockerfile = (runner / "Dockerfile").read_text(encoding="utf-8")
                runtime = (runner / "requirements.lock.txt").read_text(encoding="utf-8")
                cuda_builds = [p for p, (v, _) in lock_entries(runner / "requirements.lock.txt").items() if v.endswith("+cu128")]
                self.assertEqual(TORCH_CU128_INDEX in dockerfile, bool(cuda_builds))
                if cuda_builds:
                    self.assertIn(f"--extra-index-url {TORCH_CU128_INDEX}", dockerfile)
                    self.assertIn("--index-url https://pypi.org/simple", dockerfile)
                release = re.search(r"\nFROM nvidia/cuda:[^\s@]+-(ubuntu\d\d\.\d\d)@sha256:", dockerfile).group(1)
                python, platform = UBUNTU_PYTHON[release]
                header = runtime.split("\n", 2)[1]
                self.assertIn(f"--python-version {python} --python-platform {platform}", header)
                self.assertIn("--generate-hashes", header)
                # A week's cooldown keeps brand-new releases out of a lock, and
                # requirements.in carries the same command for the next rebuild.
                cooldown = re.search(r"--exclude-newer (\d{4}-\d{2}-\d{2}) ", header)
                self.assertIsNotNone(cooldown, "the lock was compiled without --exclude-newer")
                build_header = (runner / "requirements-build.lock.txt").read_text(encoding="utf-8").split("\n", 2)[1]
                self.assertIn(f"--exclude-newer {cooldown.group(1)} ", build_header)
                self.assertIn(f"--exclude-newer {cooldown.group(1)} ", (runner / "requirements.in").read_text(encoding="utf-8"))
                if cuda_builds:
                    self.assertIn(f"--extra-index-url {TORCH_CU128_INDEX} --index-strategy unsafe-best-match", header)

    def test_compiled_locks_keep_every_direct_requirement_and_pin(self) -> None:
        for source in sorted(RUNNERS.glob("*/requirements.in")):
            with self.subTest(runner=source.parent.name):
                locked = lock_entries(source.parent / "requirements.lock.txt")
                build = lock_entries(source.parent / "requirements-build.lock.txt")
                for line in source.read_text(encoding="utf-8").splitlines():
                    line = line.split("#", 1)[0].strip()
                    if not line:
                        continue
                    name = normalize(re.split(r"[\[<>=~!; ]", line, maxsplit=1)[0])
                    self.assertIn(name, locked)
                    exact = re.search(r"==([^\s,;]+)$", line)
                    if exact:
                        self.assertEqual(locked[name][0], exact.group(1), line)
                for package, (version, _) in build.items():
                    if package in locked:
                        self.assertEqual(locked[package][0], version, f"{package} differs between the two locks")

    def test_runners_without_python_packages_ship_no_locks(self) -> None:
        for dockerfile in sorted(RUNNERS.glob("*/Dockerfile")):
            runner = dockerfile.parent
            if runner in python_runners():
                continue
            with self.subTest(runner=runner.name):
                self.assertEqual(installs(dockerfile.read_text(encoding="utf-8")), [])
                self.assertEqual([p.name for p in runner.glob("requirements*")], [])


if __name__ == "__main__":
    unittest.main()
