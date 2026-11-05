import os
import unittest
from unittest import mock

from workflow_source_identity import workflow_source_identity


SINGLE = {
    "GITHUB_REPOSITORY": "acme-co/example-app",
    "GITHUB_SHA": "a" * 40,
    "II_OS_WORKFLOW_REPOSITORY": "acme-co/example-app",
}

SPLIT = {
    "GITHUB_REPOSITORY": "acme-co/example-implementation",
    "GITHUB_SHA": "b" * 40,
    "II_OS_IMPLEMENTATION_SHA": "b" * 40,
    "II_OS_SOURCE_SHA": "c" * 40,
    "II_OS_WORKFLOW_REPOSITORY": "acme-co/example-implementation",
    "II_OS_WORKFLOW_REPO_ROOT": "/workspace/implementation",
}


class WorkflowSourceIdentityTest(unittest.TestCase):
    def test_single_repository_uses_the_workflow_commit_for_both_roles(self) -> None:
        with mock.patch.dict(os.environ, SINGLE, clear=True):
            self.assertEqual(
                workflow_source_identity(),
                {
                    "implementation_commit": "a" * 40,
                    "source_commit": "a" * 40,
                    "workflow_repository": "acme-co/example-app",
                },
            )

    def test_the_workflow_repository_has_no_default(self) -> None:
        environment = {
            key: value
            for key, value in SINGLE.items()
            if key != "II_OS_WORKFLOW_REPOSITORY"
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            with self.assertRaisesRegex(
                RuntimeError, "II_OS_WORKFLOW_REPOSITORY is required"
            ):
                workflow_source_identity()

    def test_a_fork_running_the_workflow_is_refused(self) -> None:
        with mock.patch.dict(
            os.environ,
            {**SINGLE, "GITHUB_REPOSITORY": "someone-else/example-app"},
            clear=True,
        ):
            with self.assertRaisesRegex(
                RuntimeError, "does not match the configured repository"
            ):
                workflow_source_identity()

    def test_split_identity_keeps_implementation_and_source_distinct(self) -> None:
        with mock.patch.dict(os.environ, SPLIT, clear=True):
            self.assertEqual(
                workflow_source_identity(),
                {
                    "implementation_commit": "b" * 40,
                    "source_commit": "c" * 40,
                    "workflow_repository": "acme-co/example-implementation",
                },
            )

    def test_partial_split_identity_fails_closed(self) -> None:
        environment = {
            key: value
            for key, value in SPLIT.items()
            if key not in {"II_OS_WORKFLOW_REPO_ROOT", "II_OS_IMPLEMENTATION_SHA"}
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            with self.assertRaisesRegex(RuntimeError, "configured together"):
                workflow_source_identity()

    def test_workflow_commit_must_match_the_implementation(self) -> None:
        with mock.patch.dict(
            os.environ, {**SPLIT, "GITHUB_SHA": "a" * 40}, clear=True
        ):
            with self.assertRaisesRegex(RuntimeError, "implementation commit"):
                workflow_source_identity()


if __name__ == "__main__":
    unittest.main()
