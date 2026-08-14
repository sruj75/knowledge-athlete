#!/usr/bin/env python3
"""Focused tests for repository-owned desktop release-process guards."""

from __future__ import annotations

import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-release-process-guards.py")
SPEC = importlib.util.spec_from_file_location("release_process_guards", SCRIPT)
assert SPEC and SPEC.loader
GUARDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARDS)


def test_current_repository_release_controls_pass_without_provider_document():
    assert GUARDS.main() == 0


def test_candidate_guard_rejects_missing_exact_tag_intake_observer(monkeypatch):
    real_read = GUARDS._read

    def read_without_observer(relative_path: str, errors: list[str]) -> str:
        text = real_read(relative_path, errors)
        if relative_path == ".github/workflows/desktop_auto_release.yml":
            return text.replace("check-codemagic-tag-intake.py", "missing-intake-observer.py")
        return text

    monkeypatch.setattr(GUARDS, "_read", read_without_observer)

    errors = GUARDS.check_desktop_candidate_controls()

    assert any("check-codemagic-tag-intake.py" in error for error in errors)


def test_guard_has_no_live_provider_document_read():
    """Static ownership tripwire; the real CLI test above is behavioral."""
    source = SCRIPT.read_text(encoding="utf-8")

    assert "codemagic.yaml" not in source
    assert "missing means pass" not in source


def test_windows_only_workflows_are_excluded_before_release_guard_reads():
    assert GUARDS._is_windows_only_workflow(Path("desktop-windows-ci.yml"))
    assert GUARDS._is_windows_only_workflow(Path("desktop_windows_release.yml"))
    assert not GUARDS._is_windows_only_workflow(Path("desktop_auto_release.yml"))
