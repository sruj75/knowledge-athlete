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


def test_current_repository_release_controls_include_owned_provider_document():
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


def test_preview_guard_rejects_a_second_backend_url(monkeypatch):
    real_read = GUARDS._read

    def read_with_dual_url(relative_path: str, errors: list[str]) -> str:
        text = real_read(relative_path, errors)
        if relative_path == ".github/workflows/desktop_publish_preview.yml":
            return text + "\ndesktop_api_url:\n"
        return text

    monkeypatch.setattr(GUARDS, "_read", read_with_dual_url)

    errors = GUARDS.check_desktop_preview_controls()

    assert any("retired dual-backend field: desktop_api_url" in error for error in errors)


def test_preview_guard_rejects_a_floating_publish_key_version(monkeypatch):
    real_read = GUARDS._read

    def read_with_floating_secret(relative_path: str, errors: list[str]) -> str:
        text = real_read(relative_path, errors)
        if relative_path == "backend/deploy/runtime_env.yaml":
            return text.replace(
                "version_env_var: DESKTOP_PREVIEW_PUBLISH_KEY_VERSION",
                "version: latest",
            )
        return text

    monkeypatch.setattr(GUARDS, "_read", read_with_floating_secret)

    errors = GUARDS.check_desktop_preview_controls()

    assert "production backend must receive the preview publishing key from Secret Manager" in errors


def test_provider_guard_rejects_inherited_omi_identity(monkeypatch):
    real_read = GUARDS._read

    def read_with_inherited_identity(relative_path: str, errors: list[str]) -> str:
        text = real_read(relative_path, errors)
        if relative_path == "codemagic.yaml":
            return text + '\nINHERITED_PROVIDER_APP_ID: "66c95e6ec76853c447b8bcbb"\n'
        return text

    monkeypatch.setattr(GUARDS, "_read", read_with_inherited_identity)

    errors = GUARDS.check_codemagic_provider_controls()

    assert any("inherited provider identity" in error for error in errors)


def test_provider_guard_rejects_preview_production_publication(monkeypatch):
    real_read = GUARDS._read

    def read_with_preview_publication(relative_path: str, errors: list[str]) -> str:
        text = real_read(relative_path, errors)
        if relative_path == "codemagic.yaml":
            return text.replace(
                'PREVIEW_PUBLICATION_MODE: "preview-only"',
                'PREVIEW_PUBLICATION_MODE: "production"',
            )
        return text

    monkeypatch.setattr(GUARDS, "_read", read_with_preview_publication)

    errors = GUARDS.check_codemagic_provider_controls()

    assert any("preview-only publication fence" in error for error in errors)


def test_provider_guard_rejects_reordered_release_phases(monkeypatch):
    real_read = GUARDS._read

    def read_with_reordered_phases(relative_path: str, errors: list[str]) -> str:
        text = real_read(relative_path, errors)
        if relative_path == "codemagic.yaml":
            return text.replace(
                "    - name: Sign Sparkle archives\n",
                "    - name: Sign Sparkle archives too early\n",
            ).replace(
                "    - name: Notarize and staple release artifacts\n",
                "    - name: Sign Sparkle archives\n    - name: Notarize and staple release artifacts\n",
            )
        return text

    monkeypatch.setattr(GUARDS, "_read", read_with_reordered_phases)

    errors = GUARDS.check_codemagic_provider_controls()

    assert any("ordered release phase" in error for error in errors)


def test_windows_only_workflows_are_excluded_before_release_guard_reads():
    assert GUARDS._is_windows_only_workflow(Path("desktop-windows-ci.yml"))
    assert GUARDS._is_windows_only_workflow(Path("desktop_windows_release.yml"))
    assert not GUARDS._is_windows_only_workflow(Path("desktop_auto_release.yml"))
