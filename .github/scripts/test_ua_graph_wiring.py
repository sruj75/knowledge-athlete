#!/usr/bin/env python3
"""Exercise the UA freshness gate through the shared runner and actual pushes."""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from run_checks import load_manifest, resolve_checks
from check_release_eligibility import mapping_block, named_step_block

ROOT = Path(__file__).resolve().parents[2]


class ManifestSelectionTests(unittest.TestCase):
    def test_freshness_runs_in_both_lanes_even_for_empty_or_report_only_diffs(self) -> None:
        manifest = load_manifest(ROOT / ".github/checks-manifest.yaml")
        for lane in ("local", "ci"):
            for paths in ([], [".github/guardrail-pulse-history.jsonl"], ["backend/main.py"]):
                with self.subTest(lane=lane, paths=paths):
                    selected = {check.id for check in resolve_checks(manifest, paths, lane)}
                    self.assertIn("ua-graph-freshness", selected)


class WorkflowRoutingTests(unittest.TestCase):
    def test_required_check_cannot_be_skipped_on_metadata_events(self) -> None:
        """Static workflow tripwire: skipped GitHub checks can satisfy required status."""
        workflow = (ROOT / ".github/workflows/repo-checks.yml").read_text(encoding="utf-8")
        job = mapping_block(workflow, "ua-graph-freshness", 2)
        self.assertIsNotNone(job, "UA needs a dedicated unconditional required-check job")
        assert job is not None
        self.assertIn("name: UA Graph Freshness", job)
        self.assertNotRegex(job, r"(?m)^    (?:if|needs|strategy|continue-on-error):")
        self.assertNotRegex(job, r"(?m)^        (?:if|continue-on-error):")
        self.assertNotIn("||", job)
        checkout = named_step_block(job, "Checkout candidate", 6)
        self.assertIsNotNone(checkout)
        assert checkout is not None
        self.assertIn("uses: actions/checkout@v7", checkout)
        self.assertNotRegex(checkout, r"(?m)^          ref:")
        self.assertIn("fetch-depth: 0", checkout)
        check = named_step_block(job, "Check committed UA graph", 6)
        self.assertIsNotNone(check)
        assert check is not None
        self.assertIn("--lane ci --base HEAD --head HEAD --check-id ua-graph-freshness", check)
        self.assertLess(job.index("uses: ./.github/actions/setup-ua-graph"), job.index("run_checks.py"))
        for event in ("push", "pull_request"):
            event_block = mapping_block(workflow, event, 2)
            self.assertIsNotNone(event_block)
            self.assertNotRegex(event_block or "", r"(?m)^    paths(?:-ignore)?:")
        self.assertIn("edited, labeled, unlabeled", workflow)

    def test_all_full_manifest_callers_prepare_the_pinned_runtime(self) -> None:
        """Static setup tripwire complements the actual runner/push tests below."""
        workflow = (ROOT / ".github/workflows/repo-checks.yml").read_text(encoding="utf-8")
        for job_name in ("metadata-preflight", "hygiene"):
            job = mapping_block(workflow, job_name, 2) or ""
            with self.subTest(job=job_name):
                self.assertIn("uses: ./.github/actions/setup-ua-graph", job)
                self.assertLess(job.index("uses: ./.github/actions/setup-ua-graph"), job.index("scripts/pr-preflight"))
        release = (ROOT / ".github/actions/release-eligibility/action.yml").read_text(encoding="utf-8")
        self.assertIn("uses: ./.github/actions/setup-ua-graph", release)
        self.assertLess(release.index("uses: ./.github/actions/setup-ua-graph"), release.index("run_checks.py"))


class PushGateTests(unittest.TestCase):
    """Only unrelated checks and the checker CLI are doubles; Git and runner are real."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ua-push-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.repo = self.directory / "work"
        self.repo.mkdir()
        self.remote = self.directory / "remote.git"
        self.log = self.directory / "checks.jsonl"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            OMI_PYTHON_EXECUTABLE=sys.executable,
            PRE_PUSH_SKIP_PR_PREFLIGHT="1",
            OMI_PR_BODY_FILE=str(self.directory / "pr-body.md"),
            UA_FIXTURE_LOG=str(self.log),
            UA_FIXTURE_ALLOWED="[]",
            UA_FIXTURE_PREFLIGHT_LOG=str(self.directory / "preflight.jsonl"),
        )
        Path(self.env["OMI_PR_BODY_FILE"]).write_text("Fixture PR body\n", encoding="utf-8")
        self.git("init", "-q", "--initial-branch=main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.test")
        self.git("config", "core.hooksPath", os.devnull)
        for path in (
            "scripts/pre-push",
            "scripts/pre-push-diff-base",
            "scripts/changed-files",
            "scripts/dev-harness/_resolve_python.sh",
            ".github/scripts/run_checks.py",
            ".github/scripts/git_bash.py",
        ):
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, target)
        check = next(
            check
            for check in load_manifest(ROOT / ".github/checks-manifest.yaml").checks
            if check.id == "ua-graph-freshness"
        )
        self.write(
            ".github/checks-manifest.yaml",
            "checks:\n  - id: ua-graph-freshness\n"
            f"    command: {json.dumps(check.command)}\n    triggers: [\"all\"]\n"
            "    lanes: [\"local\", \"ci\"]\n    reason: fixture\n",
        )
        self.write(
            "scripts/ua-graph",
            '''#!/usr/bin/env python3
import argparse, json, os, subprocess
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument("command", choices=["check"])
p.add_argument("--ref", required=True)
a = p.parse_args()
ref = subprocess.check_output(["git", "rev-parse", a.ref], text=True).strip()
with Path(os.environ["UA_FIXTURE_LOG"]).open("a") as output:
    output.write(json.dumps(ref) + "\\n")
if ref not in json.loads(os.environ["UA_FIXTURE_ALLOWED"]):
    raise SystemExit("fixture: committed graph is stale for " + ref)
''',
        )
        for path in (
            "scripts/pre_push_ci_prediction.py",
            ".github/scripts/check_failure_class_guard_ratchet.py",
            ".github/scripts/check-desktop-prod-promotion-policy.py",
            ".github/scripts/check-deployment-concurrency.py",
        ):
            self.write(path, "# Unrelated boundary is successful in this push-gate fixture.\n")
        self.write(
            "scripts/pr-preflight",
            f"#!/usr/bin/env bash\nexec {shlex.quote(sys.executable)} scripts/preflight_boundary_fixture.py \"$@\"\n",
        )
        self.write(
            "scripts/preflight_boundary_fixture.py",
            '''import json, os, sys
from pathlib import Path
with Path(os.environ["UA_FIXTURE_PREFLIGHT_LOG"]).open("a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
''',
        )
        self.write("backend/scripts/needs-typecheck.sh", "#!/usr/bin/env bash\nexit 1\n")
        self.write("desktop/macos/scripts/check-gauntlet-evidence-at-head.sh", "#!/usr/bin/env bash\nexit 0\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("init", "--bare", "-q", str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-q", "origin", "main")
        self.first = self.commit_file("first", "one\n")
        self.second = self.commit_file("second", "two\n")
        self.write(".git/hooks/pre-push", "#!/usr/bin/env bash\nexec bash scripts/pre-push \"$@\"\n")
        self.git("config", "core.hooksPath", str(self.repo / ".git/hooks"))

    def write(self, path: str, text: str) -> None:
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        target.chmod(0o755)

    def git(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(["git", *args], cwd=self.repo, env=self.env, text=True, capture_output=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def commit_file(self, branch: str, content: str) -> str:
        self.git("switch", "-qc", branch, self.base)
        self.write("product.txt", content)
        self.git("add", "product.txt")
        self.git("commit", "-qm", branch)
        return self.git("rev-parse", "HEAD").stdout.strip()

    def checked_refs(self) -> list[str]:
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_stale_pushed_ref_is_rejected_despite_fresh_head_and_preflight_hatch(self) -> None:
        self.env["UA_FIXTURE_ALLOWED"] = json.dumps([self.second])
        result = self.git("push", "origin", "first:refs/heads/stale", check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("fixture: committed graph is stale for " + self.first, result.stdout + result.stderr)
        self.assertEqual(self.checked_refs(), [self.first])
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/stale").stdout, "")

    def test_every_unique_pushed_candidate_is_checked(self) -> None:
        self.env["UA_FIXTURE_ALLOWED"] = json.dumps([self.first, self.second])
        self.git("push", "origin", "first:refs/heads/a", "second:refs/heads/b", "first:refs/heads/c")
        self.assertCountEqual(self.checked_refs(), [self.first, self.second])
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/a").stdout.split()[0], self.first)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/b").stdout.split()[0], self.second)

    def test_normal_preflight_also_receives_the_pushed_candidate_and_branch(self) -> None:
        self.env.pop("PRE_PUSH_SKIP_PR_PREFLIGHT")
        self.env["UA_FIXTURE_ALLOWED"] = json.dumps([self.first])
        self.git("push", "origin", "first:refs/heads/review-this")
        self.assertEqual(self.checked_refs(), [self.first])
        calls = [json.loads(line) for line in Path(self.env["UA_FIXTURE_PREFLIGHT_LOG"]).read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][calls[0].index("--head") + 1], self.first)
        self.assertEqual(calls[0][calls[0].index("--head-branch") + 1], "review-this")

    def test_deletion_does_not_validate_an_unpublished_head(self) -> None:
        self.git("-c", f"core.hooksPath={os.devnull}", "push", "origin", "first:refs/heads/remove")
        self.git("push", "origin", ":refs/heads/remove")
        self.assertEqual(self.checked_refs(), [])
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/remove").stdout, "")

    def test_local_and_ci_runner_both_propagate_the_checker_failure(self) -> None:
        for lane in ("local", "ci"):
            with self.subTest(lane=lane):
                result = subprocess.run(
                    [
                        sys.executable,
                        ".github/scripts/run_checks.py",
                        "--lane",
                        lane,
                        "--base",
                        self.first,
                        "--head",
                        self.first,
                        "--check-id",
                        "ua-graph-freshness",
                    ],
                    cwd=self.repo,
                    env=self.env,
                    text=True,
                    capture_output=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("fixture: committed graph is stale for " + self.first, result.stdout + result.stderr)
        self.assertEqual(self.checked_refs(), [self.first, self.first])


if __name__ == "__main__":
    unittest.main()
