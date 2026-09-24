#!/usr/bin/env python3
"""Exercise policy disclosure against real Git migrations and manifest selection."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from check_policy_change_review import FIELDS, policy_paths
from run_checks import load_manifest, resolve_checks

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/scripts/check_policy_change_review.py"
REVIEW = """## Policy changes
Policy-Source: Owner request on 2026-09-24 in PR #120: allow squash merges.
Policy-Scope: Main merge methods and agent guidance.
Policy-Effect: Remove the inherited regular-merge-only restriction.
Policy-Qualifications: Preserve the fork exception and required CI checks.
"""


class PolicyReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", str(self.root / "no-hooks"))
        self.write(
            "AGENTS.md", "Never squash. Forks follow their own user's process.\n"
        )
        self.commit()
        self.base = self.git("rev-parse", "HEAD")

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=self.root,
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def write(self, path: str, content: str) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def commit(self) -> None:
        self.git("add", "--all")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "fixture")

    def run_check(
        self, body: str, changed_paths: list[str] | None = None
    ) -> subprocess.CompletedProcess:
        self.write("pr-body.txt", body)
        extra_args = []
        if changed_paths is not None:
            self.write("changed-files.txt", "\n".join(changed_paths))
            extra_args = ["--changed-files", "changed-files.txt"]
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                self.base,
                "--pr-body-file",
                "pr-body.txt",
                *extra_args,
            ],
            cwd=self.root,
            env=self.env,
            capture_output=True,
            text=True,
        )

    def migrate(self) -> None:
        (self.root / "AGENTS.md").unlink()
        self.write("openwiki/INSTRUCTIONS.md", "Land through regular-merge PRs only.\n")
        self.commit()

    def test_qualifier_losing_migration_requires_visible_review(self) -> None:
        self.migrate()
        result = self.run_check("## What changed\nMove instructions to OpenWiki.\n")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("AGENTS.md", result.stdout)
        self.assertIn("openwiki/INSTRUCTIONS.md", result.stdout)
        self.assertEqual(self.run_check(REVIEW).returncode, 0)

    def test_comments_placeholders_and_fields_outside_section_fail(self) -> None:
        self.migrate()
        for body in (
            "",
            f"<!-- {REVIEW} -->",
            f"```markdown\n{REVIEW}```\n",
            REVIEW.replace("## Policy changes", "## Other"),
        ):
            with self.subTest(body=body):
                self.assertEqual(self.run_check(body).returncode, 1)
        for field in FIELDS:
            for placeholder in ("", "TODO", "<describe>", "[source]", "N/A"):
                body = "\n".join(
                    f"{field}: {placeholder}" if line.startswith(f"{field}:") else line
                    for line in REVIEW.splitlines()
                )
                with self.subTest(field=field, placeholder=placeholder):
                    self.assertEqual(self.run_check(body).returncode, 1)

    def test_unrelated_product_change_needs_no_policy_disclosure(self) -> None:
        self.write("backend/feature.py", "value = 1\n")
        self.commit()
        self.assertEqual(self.run_check("").returncode, 0)

    def test_deleted_or_renamed_instruction_is_not_lost(self) -> None:
        self.git("mv", "AGENTS.md", "archive.md")
        self.commit()
        self.assertEqual(policy_paths(self.root, self.base, "HEAD"), ["AGENTS.md"])
        result = self.run_check("", changed_paths=["archive.md"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("AGENTS.md", result.stdout)

    def test_staged_rename_recovers_deleted_instruction_before_commit(self) -> None:
        self.git("mv", "AGENTS.md", "archive.md")
        self.assertEqual(policy_paths(self.root, self.base, "HEAD"), [])
        result = self.run_check("", changed_paths=["archive.md"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("AGENTS.md", result.stdout)
        self.assertEqual(
            self.run_check(REVIEW, changed_paths=["archive.md"]).returncode, 0
        )

    def test_local_dirty_and_untracked_instructions_use_manifest_paths(self) -> None:
        for path in ("AGENTS.md", ".agents/skills/new/SKILL.md"):
            self.write(path, "New guidance without a committed change.\n")
            with self.subTest(path=path):
                self.assertEqual(policy_paths(self.root, self.base, "HEAD"), [])
                result = self.run_check("", changed_paths=[path])
                self.assertEqual(result.returncode, 1)
                self.assertIn(path, result.stdout)
                self.assertEqual(
                    self.run_check(REVIEW, changed_paths=[path]).returncode, 0
                )
        self.write("backend/untracked.py", "value = 1\n")
        self.git("checkout", "--", "AGENTS.md")
        self.assertEqual(
            self.run_check("", changed_paths=["backend/untracked.py"]).returncode, 0
        )

    def test_component_skills_and_enforcement_paths_require_review(self) -> None:
        paths = (
            "backend/AGENTS.md",
            "desktop/CLAUDE.md",
            ".agents/skills/x/SKILL.md",
            ".conductor/settings.local.toml",
            ".github/workflows/release.yml",
            ".github/actions/release/action.yml",
            ".github/checks-manifest.yaml",
            ".github/PULL_REQUEST_TEMPLATE.md",
            ".github/scripts/run_checks.py",
            "scripts/pr-preflight",
            "scripts/preflight-check.sh",
            "scripts/pre-commit",
            "scripts/pre-push",
            "scripts/failure-class",
            ".pre-commit-config.yaml",
            "Makefile",
        )
        for path in paths:
            self.write(path, "changed\n")
        self.commit()
        self.assertEqual(policy_paths(self.root, self.base, "HEAD"), sorted(paths))
        self.assertEqual(self.run_check("").returncode, 1)

    def test_manifest_both_lanes_select_review_and_postmerge_excludes_it(self) -> None:
        manifest = load_manifest(ROOT / ".github/checks-manifest.yaml")
        review = next(
            check for check in manifest.checks if check.id == "policy-change-review"
        )
        self.assertIn("--changed-files", review.command)
        self.assertIn("{changed_files}", review.command)
        for lane in ("local", "ci"):
            selected = resolve_checks(manifest, ["AGENTS.md"], lane)
            self.assertIn("policy-change-review", {check.id for check in selected})
            selected = resolve_checks(
                manifest, ["AGENTS.md"], lane, include_pr_body_checks=False
            )
            self.assertNotIn("policy-change-review", {check.id for check in selected})
            # A rename target need not look like an instruction; the guard must
            # still inspect the deletion in its own no-renames Git diff.
            selected = resolve_checks(manifest, ["archive.md"], lane)
            self.assertIn("policy-change-review", {check.id for check in selected})


if __name__ == "__main__":
    unittest.main()
