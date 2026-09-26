#!/usr/bin/env python3
"""Exercise manifest selection and dependency preparation without network access."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from unittest.mock import call, patch

from prepare_codebase_map_check import main, prepare
from run_checks import load_manifest, resolve_checks

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "tools/codebase-map"
INSTALL = ["npm", "ci", "--no-audit", "--no-fund"]
BROWSER = ["npm", "exec", "--no", "--", "playwright", "install", "--with-deps", "chromium"]


class ViewerDependenciesTests(unittest.TestCase):
    def test_viewer_and_diagram_changes_select_both_lanes(self) -> None:
        manifest = load_manifest(ROOT / ".github/checks-manifest.yaml")
        for lane in ("local", "ci"):
            for path in (
                "tools/codebase-map/app/page.tsx",
                "tools/codebase-map/package-lock.json",
                "docs/architecture/intentive-codeflow.mmd",
                ".nvmrc",
                ".github/scripts/prepare_codebase_map_check.py",
                ".github/workflows/repo-checks.yml",
                ".github/checks-manifest.yaml",
            ):
                with self.subTest(lane=lane, path=path):
                    checks = resolve_checks(manifest, [path], lane, platform="linux")
                    self.assertIn("codebase-map", {check.id for check in checks})

    @patch("prepare_codebase_map_check.subprocess.run")
    def test_unrelated_changes_do_not_install(self, run) -> None:
        prepare(ROOT, ["backend/main.py"])
        run.assert_not_called()

    @patch("prepare_codebase_map_check.subprocess.run")
    def test_selected_check_installs_locked_packages_then_browser(self, run) -> None:
        prepare(ROOT, ["docs/architecture/intentive-codeflow.mmd"])
        self.assertEqual(
            run.call_args_list,
            [call(INSTALL, cwd=APP, check=True), call(BROWSER, cwd=APP, check=True)],
        )

    @patch("prepare_codebase_map_check.subprocess.run")
    def test_package_install_failure_stops_before_browser(self, run) -> None:
        run.side_effect = subprocess.CalledProcessError(7, INSTALL)
        with self.assertRaises(subprocess.CalledProcessError):
            prepare(ROOT, ["tools/codebase-map/package-lock.json"])
        run.assert_called_once_with(INSTALL, cwd=APP, check=True)

    @patch("prepare_codebase_map_check.subprocess.run")
    def test_browser_install_failure_is_not_swallowed(self, run) -> None:
        run.side_effect = [subprocess.CompletedProcess(INSTALL, 0), subprocess.CalledProcessError(8, BROWSER)]
        with self.assertRaises(subprocess.CalledProcessError):
            prepare(ROOT, ["tools/codebase-map/package-lock.json"])
        self.assertEqual(run.call_count, 2)

    @patch("prepare_codebase_map_check.prepare")
    @patch("prepare_codebase_map_check.changed_files")
    def test_diff_failure_returns_failure_without_install(self, changed, provision) -> None:
        changed.side_effect = subprocess.CalledProcessError(128, ["git", "diff"])
        with patch("sys.argv", ["prepare_codebase_map_check.py", "--base", "origin/main"]):
            self.assertEqual(main(), 1)
        provision.assert_not_called()


if __name__ == "__main__":
    unittest.main()
