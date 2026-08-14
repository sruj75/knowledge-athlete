#!/usr/bin/env python3
"""Regression tests for the bounded local CI-prediction selection."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from pre_push_ci_prediction import (  # noqa: E402
    DESKTOP_FLOW_LINT_INPUTS,
    github_outputs,
    resolve_impact,
    select_checks,
)


class PrePushCiPredictionTests(unittest.TestCase):
    def select(
        self,
        paths: list[str],
        contents: dict[str, str | None] | None = None,
        base_contents: dict[str, str | None] | None = None,
    ) -> list[str]:
        source_contents = contents or {}
        base_source_contents = base_contents if base_contents is not None else source_contents
        return select_checks(
            paths,
            read_text=lambda path: source_contents.get(path),
            read_base_text=lambda path: base_source_contents.get(path),
        )

    def plan(
        self,
        paths: list[str],
        contents: dict[str, str | None] | None = None,
        base_contents: dict[str, str | None] | None = None,
        event: str = "local",
    ):
        source_contents = contents or {}
        base_source_contents = base_contents if base_contents is not None else source_contents
        return resolve_impact(
            paths,
            read_text=lambda path: source_contents.get(path),
            read_base_text=lambda path: base_source_contents.get(path),
            event=event,
        )

    def test_desktop_flow_contract_sources_select_flow_lint_only(self) -> None:
        self.assertEqual(
            self.select(["desktop/macos/e2e/flows/new-flow.yaml"]),
            ["desktop-flow-lint", "desktop-ci-only"],
        )

    def test_every_desktop_flow_reader_input_selects_flow_lint(self) -> None:
        for path in DESKTOP_FLOW_LINT_INPUTS:
            with self.subTest(path=path):
                self.assertTrue(self.plan([path]).includes("desktop-flow-lint"))

    def test_canonical_swift_driver_selects_the_expensive_test_phase(self) -> None:
        plan = self.plan(["desktop/macos/scripts/run-swift-ci.sh"])
        self.assertTrue(plan.includes("desktop-swift-tests"))
        self.assertEqual(github_outputs(plan)["should_run_tests"], "true")

    def test_unknown_component_paths_select_the_normal_component_lane(self) -> None:
        desktop = self.plan(["desktop/macos/Resources/unknown-input.txt"])
        self.assertTrue(desktop.includes("desktop-ci-only"))

    def test_present_repository_inputs_never_select_absent_product_phases(self) -> None:
        for path in (
            ".github/checks-manifest.yaml",
            "backend/routers/chat_sessions.py",
            "desktop/macos/Desktop/Sources/APIClient.swift",
        ):
            with self.subTest(path=path):
                plan = self.plan([path])
                self.assertFalse(any(phase.startswith(("app-", "flutter-")) for phase in plan.phases))
                self.assertFalse(any(name.startswith(("has_app", "has_flutter")) for name in github_outputs(plan)))

    def test_selector_change_exercises_broad_resolver_fixtures(self) -> None:
        plan = self.plan(["scripts/pre_push_ci_prediction.py"])
        for phase in (
            "desktop-flow-lint",
            "desktop-swift-tests",
        ):
            with self.subTest(phase=phase):
                self.assertTrue(plan.includes(phase))

    def test_release_compile_preserves_pr_and_main_asymmetry(self) -> None:
        paths = ["desktop/macos/Resources/Info.plist"]
        self.assertFalse(self.plan(paths, event="pull_request").includes("desktop-swift-release-compile"))
        self.assertTrue(self.plan(paths, event="push").includes("desktop-swift-release-compile"))
        self.assertTrue(
            self.plan(["desktop/macos/Desktop/Package.resolved"], event="pull_request").includes(
                "desktop-swift-release-compile"
            )
        )

    def test_windows_kgworker_closure_inputs_select_only_the_targeted_test(self) -> None:
        for path in (
            "desktop/windows/scripts/kgworker-native-closure.mjs",
            "desktop/windows/scripts/kgworker-native-closure.test.mjs",
            "desktop/windows/electron-builder.config.mjs",
            "desktop/windows/package.json",
            "desktop/windows/pnpm-lock.yaml",
        ):
            self.assertEqual(self.select([path]), ["windows-kgworker-native-closure"])

    def test_unrelated_windows_changes_do_not_select_kgworker_closure_test(self) -> None:
        self.assertEqual(self.select(["desktop/windows/src/renderer/src/pages/Tasks.tsx"]), [])


if __name__ == "__main__":
    unittest.main()
