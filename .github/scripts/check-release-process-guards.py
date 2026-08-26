#!/usr/bin/env python3
"""Fail fast on the repository-owned desktop release-process contracts.

This guard intentionally owns only controls present in this checkout. The Mac
build-provider definition is deferred to S-29; GitHub-side candidate,
qualification, promotion, preview, retry, and rollback controls remain
fail-closed here.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _is_windows_only_workflow(path: Path) -> bool:
    return "windows" in path.stem.lower()


def _read(relative_path: str, errors: list[str]) -> str:
    path = ROOT / relative_path
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        errors.append(f"release control is missing or unreadable: {relative_path} ({exc})")
        return ""


def check_desktop_candidate_controls() -> list[str]:
    errors: list[str] = []
    planner = _read(".github/scripts/plan-desktop-release.py", errors)
    candidate = _read(".github/workflows/desktop_auto_release.yml", errors)

    for fragment in (
        "AUTO_RELEASE_QUIET_SECONDS = 60",
        "latest_change_age is None",
        "RECENT_TAG_WITHOUT_CHECK_SECONDS = 10 * 60",
    ):
        if fragment not in planner:
            errors.append(f"desktop auto-release planner is missing required guard fragment: {fragment}")

    for fragment in (
        "Verify native Codemagic tag intake or dispatch fenced fallback",
        "CODEMAGIC_API_TOKEN: ${{ secrets.CODEMAGIC_API_TOKEN }}",
        "check-codemagic-tag-intake.py",
        '--workflow-id "omi-desktop-swift-release"',
        "--timeout-seconds 600",
        "--dispatch-fallback-on-absence",
        "Retain native Codemagic tag intake evidence",
    ):
        if fragment not in candidate:
            errors.append(f"desktop candidate workflow is missing intake guard fragment: {fragment}")

    direct_build_endpoint = "https://api.codemagic.io/builds"
    preview_workflow = ROOT / ".github/workflows/desktop_publish_preview.yml"
    for workflow in sorted((ROOT / ".github/workflows").glob("*.yml")):
        if _is_windows_only_workflow(workflow):
            continue
        try:
            workflow_text = workflow.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            errors.append(f"release workflow is unreadable: {workflow.relative_to(ROOT)} ({exc})")
            continue
        if direct_build_endpoint in workflow_text and workflow != preview_workflow:
            errors.append(
                "normal desktop candidate controls must not start a provider build directly: "
                f"{workflow.relative_to(ROOT)}"
            )
    return errors


def check_desktop_preview_controls() -> list[str]:
    errors: list[str] = []
    dispatcher = _read(".github/workflows/desktop_publish_preview.yml", errors)
    runtime_env = _read("backend/deploy/runtime_env.yaml", errors)
    app_build = _read("desktop/macos/Desktop/Sources/AppBuild.swift", errors)
    updater = _read("desktop/macos/Desktop/Sources/UpdaterViewModel.swift", errors)
    smoke = _read("desktop/macos/scripts/smoke-signed-desktop-artifact.sh", errors)
    preview_router = _read("backend/routers/updates.py", errors)
    preview_registry = _read("backend/database/desktop_previews.py", errors)

    for fragment in (
        "workflow_dispatch:",
        "source_ref:",
        "backend_environment:",
        "backend_url:",
        "preview backend overrides must not target a production-family URL",
        "PREVIEW_BACKEND_ENVIRONMENT",
        "OMI_PYTHON_API_URL",
        "ref: main",
        "git ls-remote --exit-code origin",
        "^preview/",
        "environment: desktop-preview-publish",
        "CODEMAGIC_API_TOKEN",
        'workflowId: "omi-desktop-swift-preview"',
        'branch: "main"',
        "PREVIEW_SOURCE_SHA",
        "### Preview approval context",
        "https://github.com/${GITHUB_REPOSITORY}/commit/${PREVIEW_SOURCE_SHA}",
    ):
        if fragment not in dispatcher:
            errors.append(f"desktop preview dispatcher is missing required guard fragment: {fragment}")
    if "pull_request:" in dispatcher or "push:" in dispatcher:
        errors.append("desktop preview dispatcher must be manual-only")
    for retired in ("python_api_url", "desktop_api_url", "OMI_DESKTOP_API_URL", "PREVIEW_BACKEND_MODE"):
        if retired in dispatcher:
            errors.append(f"desktop preview dispatcher retains retired dual-backend field: {retired}")

    required_runtime_secret = (
        "            DESKTOP_PREVIEW_PUBLISH_KEY:\n"
        "              secret: DESKTOP_PREVIEW_PUBLISH_KEY\n"
        "              version_env_var: DESKTOP_PREVIEW_PUBLISH_KEY_VERSION"
    )
    if required_runtime_secret not in runtime_env:
        errors.append("production backend must receive the preview publishing key from Secret Manager")

    for fragment in (
        '@router.delete("/v2/desktop/previews/{slug}")',
        "DesktopPreviewDelistRequest",
        "delist_preview,",
        "expected_generation=request.expected_generation",
    ):
        if fragment not in preview_router:
            errors.append(f"desktop preview delisting is missing required router guard fragment: {fragment}")
    for fragment in ("def delist_preview(", "def _delist_preview_transaction(", "transaction.delete(pointer_ref)"):
        if fragment not in preview_registry:
            errors.append(f"desktop preview delisting is missing required registry guard fragment: {fragment}")
    for fragment in (
        'externalPreviewBundleIdentifierPrefix = "com.omi.preview."',
        "allowsLocalAutomation",
        "allowsSparkleUpdates",
        "hasValidExternalPreviewConfiguration",
    ):
        if fragment not in app_build:
            errors.append(f"external preview build classification is missing: {fragment}")
    if "startingUpdater: AppBuild.allowsSparkleUpdates" not in updater:
        errors.append("external preview builds must not start the shared Sparkle updater")
    for fragment in ("--preview", "IS_EXTERNAL_PREVIEW", "external preview must not carry a shared Sparkle feed"):
        if fragment not in smoke:
            errors.append(f"signed artifact smoke is missing external-preview check: {fragment}")
    return errors


def check_desktop_qualification_and_promotion() -> list[str]:
    errors: list[str] = []
    qualification = _read(".github/workflows/desktop_qualify_beta.yml", errors)
    beta_promotion = _read(".github/workflows/desktop_promote_beta.yml", errors)

    if "pull_request:" in qualification or "push:" in qualification:
        errors.append("desktop qualification runner must not execute pull-request or push workflows")
    for fragment in (
        "workflow_dispatch:",
        "self-hosted",
        "macos",
        "omi-desktop-qualification",
        'git -C "$source_dir" checkout --quiet --detach "refs/tags/$RELEASE_TAG"',
        "check-desktop-auto-beta-candidate.py",
        "--automatic",
        "actions/create-github-app-token@v3",
        "group: desktop-beta-qualification-m1",
        "cancel-in-progress: false",
    ):
        if fragment not in qualification:
            errors.append(f"desktop qualification runner is missing required guard fragment: {fragment}")
    if "desktop_promote_beta.yml" in qualification:
        errors.append("desktop qualification runner must not promote beta inside its own run")
    if "qualify-m4-mini" in qualification or "plan-fallbacks" in qualification:
        errors.append("desktop qualification runner must use only the global M1 fallback lane")

    for fragment in (
        'workflows: ["Qualify Desktop Beta Candidate"]',
        "types: [completed]",
        "github.event.workflow_run.conclusion == 'success'",
        "github.event.workflow_run.event == 'workflow_dispatch'",
        "github.event.workflow_run.head_branch",
        "github.event.workflow_run.head_sha",
        "/v2/desktop/beta/promote-qualified",
        "environment: beta",
    ):
        if fragment not in beta_promotion:
            errors.append(f"desktop beta promotion workflow is missing post-qualification guard: {fragment}")

    for relative_path in (
        ".github/workflows/desktop_promote_prod.yml",
        ".github/workflows/desktop_rollback_beta.yml",
        ".github/workflows/desktop_retry_beta_qualification.yml",
        ".github/scripts/check-desktop-auto-beta-candidate.py",
        ".github/scripts/check-codemagic-tag-intake.py",
        ".github/scripts/observe-codemagic-tag-build.py",
        "desktop/macos/scripts/smoke-signed-desktop-artifact.sh",
    ):
        if not (ROOT / relative_path).is_file():
            errors.append(f"desktop release control is missing: {relative_path}")
    return errors


def check_no_unprovisioned_beta_backend_hosts() -> list[str]:
    hosts = ("api-beta.omi.me", "pusher-beta.omi.me", "agent-beta.omi.me")
    roots = (ROOT / "desktop/macos", ROOT / ".github/workflows")
    non_shipped_parts = {".build", "test", "tests", "Tests", "test_driver"}
    errors: list[str] = []
    for root in roots:
        for path in root.rglob("*"):
            if not path.is_file() or non_shipped_parts.intersection(path.relative_to(root).parts):
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for host in hosts:
                if host in text:
                    errors.append(
                        f"shipped release source references unprovisioned beta backend host {host}: "
                        f"{path.relative_to(ROOT)}"
                    )
    return errors


def main() -> int:
    errors = [
        *check_desktop_candidate_controls(),
        *check_desktop_preview_controls(),
        *check_desktop_qualification_and_promotion(),
        *check_no_unprovisioned_beta_backend_hosts(),
    ]
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("release process guard checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
