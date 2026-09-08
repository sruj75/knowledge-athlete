#!/usr/bin/env python3
"""Workflow contracts for owner-manual macOS Beta qualification."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DesktopReleaseFlowContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = (ROOT / ".github/workflows/desktop_qualify_beta.yml").read_text(encoding="utf-8")
        self.auto_release = (ROOT / ".github/workflows/desktop_auto_release.yml").read_text(encoding="utf-8")
        self.retry = (ROOT / ".github/workflows/desktop_retry_beta_qualification.yml").read_text(encoding="utf-8")
        self.preview_workflow = (ROOT / ".github/workflows/desktop_publish_preview.yml").read_text(encoding="utf-8")

    @staticmethod
    def _named_step(workflow: str, name: str) -> str:
        marker = f"      - name: {name}\n"
        if workflow.count(marker) != 1:
            raise AssertionError(f"expected exactly one workflow step {name!r}")
        return workflow.split(marker, 1)[1].split("\n      - ", 1)[0]

    def test_owner_manual_qualification_never_registers_or_targets_a_mac_runner(self) -> None:
        self.assertIn("runs-on: ubuntu-latest", self.workflow)
        self.assertIn("environment: beta", self.workflow)
        self.assertIn("owner_evidence_asset:", self.workflow)
        for forbidden in ("self-hosted", "intentive-qual-m1-studio", "qualify-m1-studio", "codemagic-lane"):
            self.assertNotIn(forbidden, self.workflow)

    def test_exact_owner_dispatch_is_required_before_candidate_access(self) -> None:
        owner = self._named_step(self.workflow, "Require exact repository owner dispatch")
        for fragment in (
            "ACTOR: ${{ github.actor }}",
            "ACTOR_ID: ${{ github.actor_id }}",
            "REPOSITORY_OWNER_ID: ${{ github.repository_owner_id }}",
            "TRIGGERING_ACTOR: ${{ github.triggering_actor }}",
            'test "$ACTOR" = sruj75',
            'test "$ACTOR_ID" = 120443863',
            'test "$REPOSITORY_OWNER_ID" = 120443863',
            'test "$TRIGGERING_ACTOR" = sruj75',
        ):
            self.assertIn(fragment, owner)
        self.assertLess(
            self.workflow.index("Require exact repository owner dispatch"),
            self.workflow.index("Checkout exact candidate tag"),
        )

    def test_candidate_and_manual_receipt_are_bound_to_the_exact_tag_and_bytes(self) -> None:
        for fragment in (
            'ref: ${{ inputs.release_tag }}',
            'git rev-parse "$RELEASE_TAG^{commit}"',
            "check-desktop-auto-beta-candidate.py",
            "--qualification-mode owner-manual",
            "Intentive.zip intentive.dmg Intentive.Beta.zip intentive-beta.dmg",
            "desktop-smoke-result.json desktop-smoke-result-beta.json",
            "owner_manual_desktop_qualification.py verify",
            '--bundle "$STAGE/$OWNER_EVIDENCE_ASSET"',
        ):
            self.assertIn(fragment, self.workflow)

    def test_actions_evidence_name_and_contents_match_backend_admission(self) -> None:
        evidence = self._named_step(self.workflow, "Upload canonical qualification evidence artifact")
        diagnostic = self._named_step(self.workflow, "Upload backend compatibility diagnostic")
        self.assertIn("name: desktop-qualification-evidence-${{ inputs.release_tag }}", evidence)
        self.assertIn("path: ${{ runner.temp }}/desktop-owner-qualification/qualification-evidence.json", evidence)
        self.assertNotIn("backend-compatibility.json", evidence)
        self.assertIn("backend-compatibility.json", diagnostic)
        self.assertNotIn("qualification-evidence.json", diagnostic)

    def test_release_app_can_publish_only_final_evidence_after_all_read_only_validation(self) -> None:
        validation = self.workflow.index("Validate exact signed candidate and owner evidence")
        live_backend = self.workflow.index("Verify live canonical backend chat compatibility")
        token = self.workflow.index("Create release app token for final evidence publication")
        publish = self.workflow.index("Attach immutable qualification evidence")
        self.assertLess(validation, live_backend)
        self.assertLess(live_backend, token)
        self.assertLess(token, publish)
        step = self._named_step(self.workflow, "Attach immutable qualification evidence")
        self.assertIn('test "$existing" = 0', step)
        self.assertIn('asset="qualification-evidence-${TARGET_SHA}-${digest}.json"', step)
        self.assertIn("gh release upload", step)
        self.assertNotIn("--clobber", step)
        self.assertNotIn("promote", self.workflow.lower())

    def test_tagging_is_github_hosted_and_readiness_is_post_candidate_local_evidence(self) -> None:
        tag_job = self.auto_release.split("  tag-release:", 1)[1]
        self.assertIn("runs-on: ubuntu-latest", tag_job)
        self.assertNotIn("self-hosted", tag_job)
        self.assertNotIn("pre-tag-readiness.sh", tag_job)
        self.assertIn("Publish immutable tag from exact live main source", tag_job)

    def test_retry_observer_cannot_impersonate_the_owner_or_dispatch_qualification(self) -> None:
        self.assertIn("Report owner-manual retry requirement", self.retry)
        self.assertNotIn("gh workflow run", self.retry)
        self.assertNotIn("actions/create-github-app-token", self.retry)

    def test_preview_backend_validation_rejects_normalized_production_family_urls(self) -> None:
        step = self._named_step(self.preview_workflow, "Validate the declared backend environment")
        script = step.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] if line.startswith("          ") else line for line in script.splitlines())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "github-output"
            base_env = {**os.environ, "BACKEND_ENVIRONMENT": "development", "GITHUB_OUTPUT": str(output)}
            accepted = subprocess.run(
                ["bash", "-c", script],
                env={**base_env, "BACKEND_URL": "https://preview.example.test/backend"},
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            for url in ("https://api.omi.me:443/", "https://API.OMI.ME/", "https://api.omi.me./"):
                rejected = subprocess.run(
                    ["bash", "-c", script],
                    env={**base_env, "BACKEND_URL": url},
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("must not target a production-family URL", rejected.stderr)


if __name__ == "__main__":
    unittest.main()
