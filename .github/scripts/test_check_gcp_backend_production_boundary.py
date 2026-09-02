#!/usr/bin/env python3
"""Mutation tests for the rollback-first single-service production boundary."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

MODULE_PATH = ROOT / ".github/scripts/check-gcp-backend-production-boundary.py"
SPEC = importlib.util.spec_from_file_location("check_gcp_backend_production_boundary", MODULE_PATH)
assert SPEC and SPEC.loader
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class GcpBackendProductionBoundaryTests(unittest.TestCase):
    def test_current_workflow_preserves_the_rollback_first_cloud_run_only_boundary(self) -> None:
        self.assertEqual(CHECKER.validate(ROOT), [])

    def test_production_smoke_uses_the_owned_stable_cloud_run_url(self) -> None:
        workflow = (ROOT / ".github/workflows/gcp_backend.yml").read_text(encoding="utf-8")
        smoke = workflow[workflow.index(CHECKER.PROD_SMOKE) :]
        self.assertIn('[[ "$BACKEND_URL" =~ ^https://[^/]+\\.run\\.app$ ]]', workflow)
        self.assertIn('SERVING_API_URL: ${{ steps.account-deletion-target.outputs.backend_url }}', smoke)
        self.assertIn('--candidate-api-url "$SERVING_API_URL"', smoke)
        self.assertNotIn("api.omi.me", smoke)

    def test_rejects_production_boundary_regressions(self) -> None:
        original = (ROOT / ".github/workflows/gcp_backend.yml").read_text(encoding="utf-8")
        mutations = {
            "reintroduces_multi_target_input": (
                "      mode:\n",
                "      deploy_targets:\n        type: string\n      mode:\n",
            ),
            "reintroduces_backend_sync": (
                "          service: ${{ env.CLOUD_RUN_SERVICE }}\n",
                "          service: backend-sync\n",
            ),
            "omits_no_traffic_candidate_tag": (
                "--tag=${{ env.CANDIDATE_TAG }}",
                "--no-candidate-tag",
            ),
            "moves_candidate_probe_after_traffic": (CHECKER.CANDIDATE_PROBE, "Post-traffic candidate chat probe"),
            "moves_smoke_before_serving_verification": (CHECKER.PROD_SMOKE, "Smoke production candidate API"),
            "omits_owned_stable_url_guard": (
                '[[ "$BACKEND_URL" =~ ^https://[^/]+\\.run\\.app$ ]]',
                'test -n "$BACKEND_URL"',
            ),
            "reintroduces_inherited_production_domain": (
                '--candidate-api-url "$SERVING_API_URL"',
                "--candidate-api-url https://api.omi.me",
            ),
            "omits_smoke_rollback": (CHECKER.ROLLBACK_CONDITION, "false"),
            "leaks_smoke_token_to_output": (
                "trap 'rm -f \"$token_file\"' EXIT",
                "trap 'rm -f \"$token_file\"' EXIT\n          echo firebase-production-serving-token >> \"$GITHUB_OUTPUT\"",
            ),
        }
        for name, (expected, replacement) in mutations.items():
            with self.subTest(mutation=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                workflow = root / ".github/workflows/gcp_backend.yml"
                workflow.parent.mkdir(parents=True)
                self.assertIn(expected, original)
                workflow.write_text(original.replace(expected, replacement, 1), encoding="utf-8")
                self.assertTrue(CHECKER.validate(root))


if __name__ == "__main__":
    unittest.main()
