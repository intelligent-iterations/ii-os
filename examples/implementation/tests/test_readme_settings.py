"""The README's settings table lists every setting the kit's workflows read.

An operator fills in repository settings from that table. A workflow or action
that reads a `vars.*` or `secrets.*` the table leaves out fails on a fresh copy
with a setting nobody was told about, so this test keeps the table and the
workflows in step. It reads both files as text, like the workflow rules test.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest

from tests.support import KIT_ROOT

README = KIT_ROOT / "README.md"
WORKFLOW_FILES = sorted(
    path for path in (KIT_ROOT / ".github").rglob("*") if path.suffix in (".yml", ".yaml") and path.is_file()
)
SETTING_REFERENCE = re.compile(r"\b(vars|secrets)\.([A-Za-z_][A-Za-z0-9_]*)")
TABLE_ROW = re.compile(r"^\|\s*`([A-Za-z_][A-Za-z0-9_]*)`\s*\|\s*([a-z]+)\s*\|")
KIND = {"vars": "variable", "secrets": "secret"}
# GitHub provides this one to every run; nobody sets it.
AUTOMATIC = {"GITHUB_TOKEN"}


def settings_read_by_workflows() -> dict[tuple[str, str], list[str]]:
    """(name, kind) -> the workflow and action files that read it."""
    found: dict[tuple[str, str], list[str]] = {}
    for path in WORKFLOW_FILES:
        for scope, name in SETTING_REFERENCE.findall(path.read_text(encoding="utf-8")):
            if name in AUTOMATIC:
                continue
            files = found.setdefault((name, KIND[scope]), [])
            relative = path.relative_to(KIT_ROOT).as_posix()
            if relative not in files:
                files.append(relative)
    return found


def settings_section(text: str) -> list[str]:
    """The lines of the README's `## Settings` section, up to the next `## `."""
    lines = text.splitlines()
    start = lines.index("## Settings") + 1
    end = next((index for index in range(start, len(lines)) if lines[index].startswith("## ")), len(lines))
    return lines[start:end]


def settings_table_rows() -> list[tuple[str, str]]:
    """Every (name, kind) row of the tables in the README's Settings section."""
    return [
        (match.group(1), match.group(2))
        for line in settings_section(README.read_text(encoding="utf-8"))
        for match in [TABLE_ROW.match(line)]
        if match
    ]


class ReadmeSettingsTest(unittest.TestCase):
    def test_the_scan_finds_settings_and_the_table_has_rows(self) -> None:
        # Guards the two parsers: an empty scan or an empty table would make
        # the comparisons below pass without checking anything.
        self.assertTrue(settings_read_by_workflows())
        self.assertTrue(settings_table_rows())

    def test_every_setting_a_workflow_reads_is_in_the_table(self) -> None:
        listed = {name for name, _ in settings_table_rows()}
        missing = {
            f"{name} ({kind}, read by {', '.join(files)})"
            for (name, kind), files in settings_read_by_workflows().items()
            if name not in listed
        }
        self.assertEqual(missing, set(), "add these to the Settings section of README.md")

    def test_each_setting_is_listed_with_the_kind_workflows_read(self) -> None:
        listed = dict(settings_table_rows())
        for (name, kind), files in sorted(settings_read_by_workflows().items()):
            if name in listed:
                with self.subTest(setting=name):
                    self.assertEqual(listed[name], kind, f"{', '.join(files)} read it as a {kind}")

    def test_each_setting_is_listed_once(self) -> None:
        names = [name for name, _ in settings_table_rows()]
        self.assertEqual(sorted({name for name in names if names.count(name) > 1}), [])


if __name__ == "__main__":
    unittest.main()
