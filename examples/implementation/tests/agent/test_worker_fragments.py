"""The shell helpers keep the contract agent_execution composes them under.

agent_execution concatenates core, status (placeholder replaced by the run's
result file), `gh`/`curl` stubs and the prepare prefix or the execute policy
into one bash program. These tests build the same programs.
"""

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

WORKER = Path(__file__).resolve().parent / "../../scripts/agent/worker"
CORE = (WORKER / "agent-work-ticket-core.sh").read_text()
STATUS = (WORKER / "agent-work-ticket-status.sh").read_text()
PREPARE = (WORKER / "agent-work-ticket-prepare.sh").read_text()
EXECUTE = (WORKER / "agent-work-ticket-execute.sh").read_text()
BOUNDARY = "You are running inside an agent-runtime ephemeral container."
PLACEHOLDER = "'/ii-os-agent/artifacts/ii-os-agent-result.json'"
PROMPT_MARKER = '\nprompt_sha="$(file_sha256 "$prompt_file")"'
POLICY_MARKER = "\ncodex_failure_diagnostic() {"
BASH = "/bin/bash"


def quote(value):
    return "'" + str(value).replace("'", "'\"'\"'") + "'"


class WorkerFragmentMarkersTest(unittest.TestCase):
    def test_each_marker_occurs_exactly_once(self):
        self.assertEqual(PREPARE.count(BOUNDARY), 1)
        self.assertEqual(PREPARE.count("You are running inside"), 1)
        self.assertEqual(PREPARE.count(PROMPT_MARKER), 1)
        self.assertEqual(STATUS.count(PLACEHOLDER), 1)
        self.assertEqual(EXECUTE.count(POLICY_MARKER), 1)
        for source in (CORE, STATUS, PREPARE, EXECUTE):
            self.assertLessEqual(source.count("ii-os-agent-result.json"), 1)
        self.assertEqual(sum(source.count("ii-os-agent-result.json") for source in (CORE, PREPARE, EXECUTE)), 0)
        self.assertLess(PREPARE.index(BOUNDARY), PREPARE.index(PROMPT_MARKER))

    def test_helpers_parse_and_hold_no_credential_or_publication_path(self):
        for name in ("core", "status", "prepare", "execute"):
            path = WORKER / f"agent-work-ticket-{name}.sh"
            self.assertEqual(subprocess.run([BASH, "-n", str(path)]).returncode, 0, name)
            text = path.read_text()
            for forbidden in ("git push", "gh api", "gh pr", "gh issue", "curl ", "GH_TOKEN", "GITHUB_TOKEN",
                              "x-access-token", "CODEX_AUTH", "codex exec"):
                self.assertNotIn(forbidden, text, f"{name}: {forbidden}")


@unittest.skipUnless(shutil.which("jq"), "jq is required")
class WorkerFragmentBehaviourTest(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory(prefix="worker-fragments-")
        self.root = Path(self._temporary.name).resolve()
        self.addCleanup(self._temporary.cleanup)
        self.result = self.root / "result.json"
        self.environment = {
            "PATH": os.environ["PATH"], "HOME": str(self.root),
            "IIAUTO_ISSUE_URL": "https://github.com/acme-co/example-app/issues/17",
            "IIAUTO_STREAM_ID": "github:acme-co/example-app#17", "IIAUTO_WORK_ROOT": str(self.root),
            "IIAUTO_REPOSITORY_ID": "4242", "IIAUTO_PROJECT_ITEM_ID": "PVTI_example17",
            "IIAUTO_DISPATCH_ID": "human:PVTI_example17", "IIAUTO_RESULT_FILE": str(self.result),
            "IIAUTO_DEFER_GITHUB_MUTATIONS": "1", "IIAUTO_GITHUB_APP_SLUG": "example-app-bot",
            "IIAUTO_AUTOMATION_ALLOWED_APP_SLUGS": "example-app-bot",
        }

    def run_program(self, body, environment=None, result_path=None):
        status = STATUS.replace(PLACEHOLDER, quote(result_path or self.result))
        program = self.root / "program.sh"
        program.write_text("\n".join(["set -euo pipefail", CORE, status, "gh() { return 125; }",
                                      "curl() { return 125; }", body, ""]))
        return subprocess.run([BASH, str(program)], cwd=self.root, capture_output=True, text=True,
                              env={**self.environment, **(environment or {})}, timeout=30)

    def prepare(self, **ticket):
        approved = {"schema_version": 1, "project_id": "PVT_example", "project_item_id": "PVTI_example17",
                    "repository_id": 4242, "repository": "acme-co/example-app", "issue_number": 17,
                    "title": "Add a dark-mode toggle", "body": "Add a toggle.", "activation_response": "", **ticket}
        path = self.root / "ticket-prompt.json"
        path.write_bytes(json.dumps(approved).encode())
        environment = {"IIAUTO_TICKET_PROMPT_FILE": str(path),
                       "IIAUTO_TICKET_PROMPT_SHA256": hashlib.sha256(path.read_bytes()).hexdigest()}
        return self.run_program(PREPARE[:PREPARE.index(PROMPT_MARKER)], environment)

    def test_the_prompt_prefix_renders_and_seeds_a_bounded_setup_failure(self):
        completed = self.prepare()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        prompt = (self.root / "prompt.md").read_text()
        self.assertEqual(prompt.count(BOUNDARY), 1)
        self.assertIn("Title: Add a dark-mode toggle", prompt)
        result = json.loads(self.result.read_text())
        self.assertEqual((result["outcome"], result["status"], result["pull_request"]), ("not_ready", "todo", None))
        self.assertEqual(result["automation_failure"]["code"], "agent_worker_setup_failed")
        self.assertEqual(result["dispatch_id"], "human:PVTI_example17")

    def test_a_mismatched_approved_ticket_stops_with_its_reason_recorded(self):
        completed = self.prepare(issue_number=18)
        self.assertEqual(completed.returncode, 2)
        self.assertFalse((self.root / "prompt.md").exists())
        self.assertEqual(json.loads(self.result.read_text())["automation_failure"],
                         {"code": "agent_worker_setup_failed", "detail": "the approved ticket prompt identity is invalid"})

    def test_a_changed_approved_ticket_is_refused(self):
        path = self.root / "ticket-prompt.json"
        path.write_text("{}")
        completed = self.run_program(PREPARE[:PREPARE.index(PROMPT_MARKER)], {
            "IIAUTO_TICKET_PROMPT_FILE": str(path), "IIAUTO_TICKET_PROMPT_SHA256": "0" * 64})
        self.assertEqual(completed.returncode, 2)
        self.assertIn("changed before execution", completed.stderr)

    def deferred_state(self):
        return ("owner=acme-co repo=example-app issue_number=17 deferred_outcome=not_ready deferred_status=todo "
                "deferred_pull_request=null deferred_failure_json=null "
                f"deferred_comments_file={quote(self.root / 'comments.jsonl')}; : > \"$deferred_comments_file\"")

    def test_the_result_is_written_only_to_the_replaced_path(self):
        other = self.root / "elsewhere.json"
        completed = self.run_program(self.deferred_state() + "\nwrite_deferred_outcome not_ready todo",
                                     {"IIAUTO_RESULT_FILE": str(other)})
        self.assertNotEqual(completed.returncode, 0)
        self.assertFalse(other.exists())
        self.assertFalse(self.result.exists())

    def test_github_mutations_exist_only_as_deferred_records(self):
        body = self.deferred_state() + "\nissue_comment 'Synthetic note.'"
        completed = self.run_program(body)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(self.result.read_text())["comments"], ["Synthetic note."])
        refused = self.run_program(body, {"IIAUTO_DEFER_GITHUB_MUTATIONS": "0"})
        self.assertEqual(refused.returncode, 2)
        self.assertIn("published by the trusted controller only", refused.stderr)

    def test_project_status_is_recorded_for_the_configured_app_only(self):
        project = {"IIAUTO_PROJECT_ID": "PVT_example", "IIAUTO_STATUS_FIELD_ID": "PVTSSF_status",
                   "IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID": "opt-human", "IIAUTO_STATUS_QA_FAILED_OPTION_ID": "opt-failed"}
        body = self.deferred_state() + "\nset_project_status opt-human 'Which theme?' 'Comment with the theme name.' || exit 7"
        completed = self.run_program(body, project)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(self.result.read_text())
        self.assertEqual((result["outcome"], result["status"]), ("not_ready", "needs_human_input"))
        self.assertIn("Actor: example-app-bot[bot] (Bot)", result["comments"][0])
        for name, environment in {
            "unlisted app": {**project, "IIAUTO_AUTOMATION_ALLOWED_APP_SLUGS": "another-bot"},
            "missing app": {**project, "IIAUTO_GITHUB_APP_SLUG": ""},
            "not deferred": {**project, "IIAUTO_DEFER_GITHUB_MUTATIONS": "0"},
        }.items():
            with self.subTest(name):
                self.result.unlink(missing_ok=True)
                self.assertEqual(self.run_program(body, environment).returncode, 7)
                self.assertFalse(self.result.exists())
        human_only = self.deferred_state() + "\nset_project_status opt-failed reason evidence || exit 7"
        self.assertEqual(self.run_program(human_only, project).returncode, 7)

    def test_readiness_requires_a_live_artifact_method_and_verification(self):
        ready = ("- Human input needed: No.\n- Ready for QA: Yes.\n"
                 "- QA artifact: https://dev.example-app.example.com/settings\n"
                 "- QA method: Open settings, toggle dark mode, reload and confirm it persists.\n"
                 "- Verification: Ran the settings tests; all passed.\n")
        cases = {
            ready: "",
            ready.replace("https://dev.example-app.example.com/settings",
                          "https://github.com/acme-co/example-app/pull/9"): "No deployed or live-verifiable QA artifact was reported.",
            ready.replace("Human input needed: No.", "Human input needed: Yes."):
                "The result note says human input is needed but does not describe the exact human input or action required.",
            "": "No .auto-agent-result.md status note was produced.",
        }
        for note, expected in cases.items():
            with self.subTest(expected=expected):
                completed = self.run_program(f"open_pr=0\nqa_readiness_blockers {quote(note)} '' 0")
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(completed.stdout, expected)


if __name__ == "__main__":
    unittest.main()
