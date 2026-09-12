#!/usr/bin/env python3
"""Unit tests for desktop changelog tooling (stdlib unittest).

Regression coverage for #9717: read_json/write_json must always use UTF-8 so a
contributor on a non-UTF-8 host locale (e.g. GBK on native Windows Python) does
not crash with a UnicodeDecodeError. The CI host is UTF-8, so a plain round-trip
would not catch a missing encoding; these tests assert the encoding is forwarded
on every platform.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "desktop_changelog", Path(__file__).with_name("desktop-changelog.py")
)
changelog = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(changelog)

_CHECK_SPEC = importlib.util.spec_from_file_location(
    "check_desktop_changelog", Path(__file__).with_name("check-desktop-changelog.py")
)
checker = importlib.util.module_from_spec(_CHECK_SPEC)
_CHECK_SPEC.loader.exec_module(checker)


class EncodingTests(unittest.TestCase):
    def test_read_json_forces_utf8(self) -> None:
        captured: dict[str, object] = {}
        real_read_text = Path.read_text

        def spy(self: Path, *args: object, **kwargs: object) -> str:
            captured["encoding"] = kwargs.get("encoding")
            return real_read_text(self, *args, **kwargs)

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "changelog.json"
            path.write_text('{"note": "“curly”"}', encoding="utf-8")
            with unittest.mock.patch.object(Path, "read_text", spy):
                self.assertEqual(changelog.read_json(path), {"note": "“curly”"})
        self.assertEqual(captured["encoding"], "utf-8")

    def test_write_json_forces_utf8(self) -> None:
        captured: dict[str, object] = {}
        real_write_text = Path.write_text

        def spy(self: Path, *args: object, **kwargs: object) -> int:
            captured["encoding"] = kwargs.get("encoding")
            return real_write_text(self, *args, **kwargs)

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out" / "changelog.json"
            with unittest.mock.patch.object(Path, "write_text", spy):
                changelog.write_json(path, {"note": "“curly”"})
        self.assertEqual(captured["encoding"], "utf-8")

    def test_round_trip_preserves_non_ascii(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "changelog.json"
            payload = {"note": "“curly” — café"}
            changelog.write_json(path, payload)
            self.assertEqual(changelog.read_json(path), payload)


class ChangelogRequirementTests(unittest.TestCase):
    def test_qualification_helper_push_without_pr_label_preserves_product_gate(self) -> None:
        # PR #110 passed with the internal-only label, then its main push failed.
        # Exercise the actual CLI over Git commits: no label or --skip is present.
        script = Path(__file__).with_name("check-desktop-changelog.py").resolve()
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        for include_product_source in (False, True):
            with (
                self.subTest(include_product_source=include_product_source),
                tempfile.TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)

                def git(*args: str) -> str:
                    return subprocess.check_output(
                        [
                            "git", "-c", "user.name=CI Test",
                            "-c", "user.email=ci@example.invalid",
                            "-c", "commit.gpgsign=false",
                            "-c", "core.hooksPath=/dev/null", *args,
                        ],
                        cwd=root,
                        env=env,
                        text=True,
                        stderr=subprocess.PIPE,
                    ).strip()

                git("init", "--quiet")
                git("commit", "--quiet", "--allow-empty", "-m", "baseline")
                base = git("rev-parse", "HEAD")
                helper = root / "desktop/macos/scripts/qualification-desktop-command.py"
                helper.parent.mkdir(parents=True)
                helper.write_text("# Internal qualification controller\n", encoding="utf-8")
                if include_product_source:
                    source = root / "desktop/macos/Desktop/Sources/AppDelegate.swift"
                    source.parent.mkdir(parents=True)
                    source.write_text("// User-facing application change\n", encoding="utf-8")
                git("add", ".")
                git("commit", "--quiet", "-m", "change")
                result = subprocess.run(
                    [sys.executable, str(script), "--base", base, "--head", "HEAD"],
                    cwd=root,
                    env=env,
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(result.returncode, 1 if include_product_source else 0, result.stderr)
                if include_product_source:
                    self.assertIn("AppDelegate.swift", result.stderr)
                    self.assertNotIn("qualification-desktop-command.py", result.stderr)
                else:
                    self.assertIn("No desktop changes require a changelog entry.", result.stdout)

    def test_internal_release_controls_are_exempt_but_product_source_is_not(self) -> None:
        for path in (
            # Local Dev entrypoints are not included in signed Beta/Stable;
            # this must hold on post-merge push without any PR label.
            "desktop/macos/run.sh",
            "desktop/macos/scripts/omi-dev",
            "desktop/macos/scripts/bundle-size-harness.sh",
            "desktop/macos/scripts/desktop-core-harness.sh",
            "desktop/macos/docs/release.md",
            "desktop/macos/scripts/qualify-desktop-beta.sh",
            "desktop/macos/scripts/collect-owner-manual-beta-qualification.sh",
            "desktop/macos/scripts/codemagic-release.sh",
            # Sibling qualification-runner helper (EXEMPT_DESKTOP_PATHS).
            "desktop/macos/scripts/qualification-swift-cache.sh",
            "desktop/macos/scripts/qualification-lease-command.sh",
            # CI-only flow validation and its shared source inventory do not
            # alter the desktop application users receive.
            "desktop/macos/scripts/desktop-flow-lint.py",
            "desktop/macos/scripts/desktop_flow_contract.py",
            # The continuity gauntlet and its flow definitions are internal
            # qualification infrastructure; PR labels cannot protect main push CI.
            "desktop/macos/scripts/agent-continuity-gauntlet-lib.py",
            "desktop/macos/e2e/CORE_E2E.md",
            "desktop/macos/e2e/flows/agent-continuity.yaml",
            # Test files are never user-facing app changes (EXEMPT_DESKTOP_PATH_PREFIXES).
            # #10374's timeout bump touched this file; without the exemption the
            # post-merge push run of the changelog gate reddened main (#10387).
            "desktop/macos/tests/test-qualify-desktop-beta-contract.sh",
            "desktop/macos/tests/some-other-desktop-test.sh",
            # Agent test repairs must also pass the post-merge push lane,
            # which cannot inherit a PR-only no-changelog-needed label.
            "desktop/macos/agent/tests/control-tools.test.ts",
            "desktop/macos/agent/tests/agent-spawn-journal.test.ts",
            "desktop/macos/agent/tests/kernel-fakes.ts",
            # Generated Swift is derived from the OpenAPI contract, never a
            # user-facing app note (EXEMPT_DESKTOP_PATH_PREFIXES).
            "desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift",
        ):
            with self.subTest(path=path):
                self.assertFalse(checker.is_desktop_change_requiring_changelog(path))

        # Product source still requires a changelog — the exemptions must not leak.
        # Note the hand-written Sources file is NOT under Sources/Generated/.
        for path in (
            "desktop/macos/Desktop/Sources/AppDelegate.swift",
            "desktop/macos/scripts/some-user-facing-script.sh",
            "desktop/macos/scripts/prepare-release-libwebp.sh",
            "desktop/macos/agent/src/runtime/control-tools.ts",
            "desktop/macos/agent/tests-extra/runtime.ts",
        ):
            with self.subTest(path=path):
                self.assertTrue(checker.is_desktop_change_requiring_changelog(path))


if __name__ == "__main__":
    unittest.main()
