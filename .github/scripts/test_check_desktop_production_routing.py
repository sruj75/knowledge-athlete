#!/usr/bin/env python3
"""Regression contract for retained macOS production routing."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / ".github/scripts/check-desktop-production-routing.py"
SPEC = importlib.util.spec_from_file_location("check_desktop_production_routing", MODULE_PATH)
assert SPEC and SPEC.loader
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


def _copy_protected_sources(root: Path) -> None:
    for relative_path in CHECKER.REQUIRED_PRODUCTION_FRAGMENTS:
        target = root / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text((ROOT / relative_path).read_text(encoding="utf-8"), encoding="utf-8")


class DesktopProductionRoutingContractTests(unittest.TestCase):
    def test_current_config_is_pinned(self) -> None:
        self.assertEqual(CHECKER.validate(ROOT), [])

    def test_rejects_reintroduced_retired_gke_desktop_backend_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_protected_sources(root)
            retired = root / "backend/charts/desktop-backend/Chart.yaml"
            retired.parent.mkdir(parents=True)
            retired.write_text("apiVersion: v2\nname: desktop-backend\n", encoding="utf-8")

            errors = CHECKER.validate(root)

            self.assertTrue(any("retired GKE desktop-backend ownership" in error for error in errors), errors)

    def test_ignores_windows_only_workflows_without_reading_them_as_mac_ownership(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_protected_sources(root)
            windows_workflow = root / ".github/workflows/desktop_windows_release.yml"
            windows_workflow.parent.mkdir(parents=True)
            windows_workflow.write_text(
                "jobs:\n  release:\n    steps:\n      - run: helm upgrade desktop-backend\n",
                encoding="utf-8",
            )

            self.assertEqual(CHECKER.validate(root), [])

    def test_rejects_mutated_production_routing_or_identity(self) -> None:
        for relative_path, fragments in CHECKER.REQUIRED_PRODUCTION_FRAGMENTS.items():
            for fragment in fragments:
                with self.subTest(path=relative_path, fragment=fragment), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    _copy_protected_sources(root)
                    target = root / relative_path
                    target.write_text(
                        target.read_text(encoding="utf-8").replace(fragment, "MUTATED_PRODUCTION_IDENTITY"),
                        encoding="utf-8",
                    )

                    self.assertTrue(CHECKER.validate(root))

    def test_rejects_legacy_beta_or_staging_tokens(self) -> None:
        for token in CHECKER.FORBIDDEN_ROUTING_TOKENS:
            with self.subTest(token=token), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_protected_sources(root)
                target = root / CHECKER.DESKTOP_BACKEND_ENVIRONMENT_PATH
                target.write_text(target.read_text(encoding="utf-8") + f"\n// {token}\n", encoding="utf-8")

                self.assertTrue(CHECKER.validate(root))


if __name__ == "__main__":
    unittest.main()
