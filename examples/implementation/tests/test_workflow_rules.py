"""Structural rules every kit workflow and composite action keeps.

These read the YAML as text on purpose: the public gate runs with only the
Python standard library, and each rule is a line-level property anyway.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest

from tests.support import KIT_ROOT

WORKFLOWS = sorted((KIT_ROOT / ".github" / "workflows").glob("*.yml"))
ACTIONS = sorted((KIT_ROOT / ".github" / "actions").glob("*/action.yml"))
PINNED_USE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # \S.*$")
FORBIDDEN_USES = ("actions/upload-artifact", "actions/download-artifact", "actions/cache")


def lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def top_level_keys(path: Path) -> dict[str, str]:
    keys = {}
    for line in lines(path):
        match = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if match:
            keys[match.group(1)] = match.group(2)
    return keys


def run_blocks(path: Path) -> list[tuple[int, str]]:
    """Every line that belongs to a `run:` value, with its line number."""
    found: list[tuple[int, str]] = []
    source = lines(path)
    index = 0
    while index < len(source):
        line = source[index]
        match = re.match(r"^(\s*)(?:- )?run:\s*(.*)$", line)
        if not match:
            index += 1
            continue
        indent = len(match.group(1))
        found.append((index + 1, match.group(2)))
        index += 1
        while index < len(source) and (not source[index].strip() or len(source[index]) - len(source[index].lstrip()) > indent):
            found.append((index + 1, source[index]))
            index += 1
    return found


def jobs(path: Path) -> dict[str, list[str]]:
    """Job id -> the job's lines (jobs are two-space indented under `jobs:`)."""
    result: dict[str, list[str]] = {}
    current = None
    inside = False
    for line in lines(path):
        if re.match(r"^jobs:\s*$", line):
            inside = True
            continue
        if inside and re.match(r"^\S", line):
            inside = False
        if not inside:
            continue
        match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if match:
            current = match.group(1)
            result[current] = []
        elif current is not None:
            result[current].append(line)
    return result


class WorkflowRulesTest(unittest.TestCase):
    def test_the_kit_ships_workflows(self) -> None:
        self.assertTrue(WORKFLOWS)
        self.assertTrue(ACTIONS)

    def test_workflows_are_dispatch_only_with_no_default_permissions(self) -> None:
        # A reviewed reusable body (the agent workflows) is triggered only by
        # workflow_call, and only from a workflow in this kit.
        called = {match.group(1) for path in WORKFLOWS for line in lines(path)
                  for match in [re.match(r"^\s*uses:\s*\S*\.github/workflows/([A-Za-z0-9_.-]+\.yml)(?:@[0-9a-f]{40})?(?:\s.*)?$", line)] if match}
        for path in WORKFLOWS:
            with self.subTest(workflow=path.name):
                text = path.read_text(encoding="utf-8")
                if path.name in called and "workflow_dispatch" not in text:
                    self.assertIn("\non:\n  workflow_call:\n", text)
                else:
                    self.assertIn("\non:\n  workflow_dispatch:\n", text)
                # Inspect the trigger keys, not the whole file: script text may
                # legitimately mention words such as an API error code.
                source = lines(path)
                start = source.index("on:") + 1
                end = next((index for index in range(start, len(source)) if re.match(r"^\S", source[index])), len(source))
                triggers = {match.group(1) for line in source[start:end] for match in [re.match(r"^  ([A-Za-z_]+):", line)] if match}
                for trigger in ("pull_request", "pull_request_target", "push", "schedule", "workflow_run", "issue_comment"):
                    self.assertNotIn(trigger, triggers)
                self.assertEqual(top_level_keys(path).get("permissions"), "{}")

    def test_every_job_has_a_timeout_permissions_and_a_settings_runner(self) -> None:
        for path in WORKFLOWS:
            for job, body in jobs(path).items():
                with self.subTest(workflow=path.name, job=job):
                    text = "\n".join(body)
                    self.assertRegex(text, r"(^|\n)    permissions:")
                    reusable = [line for line in body if line.startswith("    uses:")]
                    if reusable:
                        # GitHub rejects runs-on and timeout-minutes on a job that
                        # calls a reusable workflow; the called body carries them.
                        self.assertRegex(reusable[0], r"^    uses: (\./\.github/workflows/\S+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/\S+@[0-9a-f]{40}( # \S.*)?)$")
                        continue
                    self.assertRegex(text, r"\n    timeout-minutes: \d+")
                    runs_on = [line for line in body if line.startswith("    runs-on:")]
                    if runs_on:
                        self.assertRegex(text, r"\n    timeout-minutes: \d+")
                        self.assertRegex(runs_on[0], r"runs-on: \$\{\{ fromJSON\(vars\.II_OS_[A-Z]+_RUNS_ON\) \}\}$")
                    else:
                        # GitHub rejects timeout-minutes on a job that calls a
                        # reusable workflow; the jobs it calls carry their own,
                        # and they are checked here as kit workflows too.
                        self.assertRegex(text, r"\n    uses: \./")
                        self.assertNotIn("timeout-minutes:", text)

    def test_generation_runs_are_named_and_serialised_by_request(self) -> None:
        for path in WORKFLOWS:
            text = path.read_text(encoding="utf-8")
            if "ii_request_id:" not in text:
                continue
            with self.subTest(workflow=path.name):
                self.assertRegex(text, r"\nrun-name: .* \$\{\{ inputs\.ii_request_id \}\}\n")
                self.assertRegex(text, r"\nconcurrency:\n  group: [a-z0-9-]+-\$\{\{ inputs\.ii_request_id \}\}\n")

    def test_third_party_actions_are_pinned_and_paid_storage_is_unused(self) -> None:
        for path in WORKFLOWS + ACTIONS:
            for number, line in enumerate(lines(path), 1):
                match = re.match(r"^\s*(?:- )?uses:\s*(.+)$", line)
                if not match:
                    continue
                target = match.group(1).strip()
                with self.subTest(file=path.name, line=number):
                    self.assertFalse(target.startswith(FORBIDDEN_USES), target)
                    if not target.startswith("./"):
                        self.assertRegex(target, PINNED_USE)

    def test_no_expression_is_interpolated_into_a_shell_script(self) -> None:
        for path in WORKFLOWS + ACTIONS:
            for number, line in run_blocks(path):
                with self.subTest(file=path.name, line=number):
                    self.assertNotIn("${{", line)

    def test_checkouts_do_not_keep_credentials(self) -> None:
        for path in WORKFLOWS:
            text = path.read_text(encoding="utf-8")
            with self.subTest(workflow=path.name):
                self.assertEqual(text.count("uses: actions/checkout@"), text.count("persist-credentials: false"))

    def test_composite_actions_are_composite(self) -> None:
        for path in ACTIONS:
            with self.subTest(action=path.parent.name):
                self.assertIn("\nruns:\n  using: composite\n", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
