#!/usr/bin/env python3
"""Fail fast on the repository-owned desktop release-process contracts."""

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
        '--app-id "6a8ff0296fc70d39540cb56a"',
        '--workflow-id "intentive-macos-release"',
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
    product_identity = _read("desktop/macos/Desktop/Sources/OmiSupport/DesktopProductIdentity.swift", errors)
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
        'branch: "main"',
        "PREVIEW_SOURCE_SHA",
        'CODEMAGIC_APP_ID: 6a8ff0296fc70d39540cb56a',
        'workflowId: "intentive-macos-preview"',
        'test "$REPOSITORY" = "sruj75/knowledge-athlete"',
        "Validate an approved production preview backend",
        "validate-intentive-production-origin.py",
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
        "externalPreviewBundleIdentifierPrefix = DesktopProductIdentity.previewBundlePrefix",
        "allowsLocalAutomation",
        "allowsSparkleUpdates",
        "hasValidExternalPreviewConfiguration",
    ):
        if fragment not in app_build:
            errors.append(f"external preview build classification is missing: {fragment}")
    if 'previewBundlePrefix = "com.heyintentive.intentive.preview."' not in product_identity:
        errors.append("typed product identity is missing the owned Intentive preview namespace")
    if "startingUpdater: AppBuild.allowsSparkleUpdates" not in updater:
        errors.append("external preview builds must not start the shared Sparkle updater")
    for fragment in ("--preview", "IS_EXTERNAL_PREVIEW", "external preview must not carry a shared Sparkle feed"):
        if fragment not in smoke:
            errors.append(f"signed artifact smoke is missing external-preview check: {fragment}")
    return errors


def check_codemagic_provider_controls() -> list[str]:
    errors: list[str] = []
    provider = _read("codemagic.yaml", errors)
    driver = _read("desktop/macos/scripts/codemagic-release.sh", errors)
    release_graph_paths = (
        ".github/workflows/desktop_auto_release.yml",
        ".github/workflows/desktop_beta_admission_control.yml",
        ".github/workflows/desktop_breakglass_credential_preflight.yml",
        ".github/workflows/desktop_breakglass_rollout_beta.yml",
        ".github/workflows/desktop_promote_beta.yml",
        ".github/workflows/desktop_promote_prod.yml",
        ".github/workflows/desktop_publish_preview.yml",
        ".github/workflows/desktop_qualify_beta.yml",
        ".github/workflows/desktop_recover_beta.yml",
        ".github/workflows/desktop_release_doctor.yml",
        ".github/workflows/desktop_retry_beta_qualification.yml",
        ".github/workflows/desktop_rollback_beta.yml",
        ".github/scripts/check-desktop-prod-promotion-policy.py",
        ".github/actionlint.yaml",
    )
    release_graph = {path: _read(path, errors) for path in release_graph_paths}

    for fragment in (
        "intentive-macos-release:",
        "intentive-macos-preview:",
        'APP_NAME: "Intentive"',
        'BUNDLE_ID: "com.heyintentive.intentive"',
        'BETA_BUNDLE_ID: "com.heyintentive.intentive.beta"',
        'APPLE_TEAM_ID: "24D6NXS6H7"',
        'CODEMAGIC_APP_ID: "6a8ff0296fc70d39540cb56a"',
        'GITHUB_REPOSITORY: "sruj75/knowledge-athlete"',
        'PREVIEW_PUBLICATION_MODE: "preview-only"',
        "intentive_macos_signing",
        "intentive_macos_release",
        "intentive_macos_preview",
        "scripts/codemagic-release.sh validate",
        "desktop/macos/build/Intentive.zip",
        "desktop/macos/build/intentive.dmg",
        "desktop/macos/build/Intentive.Beta.zip",
        "desktop/macos/build/intentive-beta.dmg",
        "desktop/macos/build/desktop-smoke-result.json",
    ):
        if fragment not in provider:
            errors.append(f"Codemagic provider document is missing owned contract fragment: {fragment}")

    release_phases = (
        "    - name: Build universal app and dSYM\n",
        "    - name: Prepare pinned libwebp and sign nested code\n",
        "    - name: Sign outer release bundle\n",
        "    - name: Notarize and staple release artifacts\n",
        "    - name: Sign Sparkle archives\n",
        "    - name: Upload exact dSYM to Sentry\n",
        "    - name: Smoke signed artifacts\n",
        "    - name: Publish immutable artifact and evidence\n",
    )
    previous = -1
    for phase in release_phases:
        position = provider.find(phase)
        if position < 0 or position <= previous:
            errors.append(f"Codemagic provider document is missing ordered release phase: {phase.strip()}")
        previous = position

    for fragment in (
        '"${CM_TAG}^{commit}"',
        'git checkout --detach "$PREVIEW_SOURCE_SHA"',
        "INTENTIVE_BETA_FIREBASE_PLIST_BASE64",
        "MACOS_DEVELOPER_ID_P12_PASSWORD",
        "APP_STORE_CONNECT_PRIVATE_KEY",
        "SPARKLE_PRIVATE_KEY",
        "SENTRY_AUTH_TOKEN",
        "prepare-release-libwebp.sh",
        "create-intentive-beta-variant.sh",
        "publish-desktop-debug-symbols.sh",
        "smoke-signed-desktop-artifact.sh",
        "--auth-storage-canary",
        'gh release create "$CM_TAG"',
        "--if-generation-match=0",
        "validate-intentive-production-origin.py",
    ):
        if fragment not in driver:
            errors.append(f"Codemagic release driver is missing required boundary: {fragment}")

    if 'PREVIEW_PUBLICATION_MODE: "preview-only"' not in provider:
        errors.append("Codemagic preview workflow is missing its preview-only publication fence")

    inherited_values = (
        "66c95e6ec76853c447b8bcbb",
        "omi-desktop-swift-release",
        "omi-desktop-swift-preview",
        "BasedHardware/omi",
        "api.omi.me",
        "api.omiapi.com",
        "macos.omi.me",
        "com.omi.computer-macos",
        "omi_macos_updates",
        "OMI_BOT",
        "Omi Bot",
        "runs-on: [self-hosted, macos, omi-desktop-qualification, omi-qual-m1-studio]",
        "- omi-desktop-qualification",
        "- omi-qual-m1-studio",
    )
    release_controls = {
        "codemagic.yaml": provider,
        "desktop/macos/scripts/codemagic-release.sh": driver,
        **release_graph,
    }
    for relative_path, text in release_controls.items():
        for value in inherited_values:
            if value in text:
                errors.append(f"Mac release control {relative_path} retains inherited provider identity: {value}")

    sensitive_backend_workflows = {
        ".github/workflows/desktop_beta_admission_control.yml": "ADMIN_KEY=\"$(gcloud",
        ".github/workflows/desktop_breakglass_credential_preflight.yml": "ADMIN_KEY=\"$(gcloud",
        ".github/workflows/desktop_breakglass_rollout_beta.yml": "ADMIN_KEY=\"$(gcloud",
        ".github/workflows/desktop_promote_beta.yml": "BETA_PROMOTION_TOKEN: ${{ secrets.BETA_PROMOTION_TOKEN }}",
        ".github/workflows/desktop_promote_prod.yml": "ADMIN_KEY=$(gcloud",
        ".github/workflows/desktop_rollback_beta.yml": "ADMIN_KEY=\"$(gcloud",
    }
    for relative_path, credential_marker in sensitive_backend_workflows.items():
        workflow = release_graph[relative_path]
        trusted_checkout = workflow.find("ref: main")
        validator = workflow.find("validate-intentive-production-origin.py")
        credential = workflow.find(credential_marker)
        if min(trusted_checkout, validator, credential) < 0 or not trusted_checkout < validator < credential:
            errors.append(
                "sensitive desktop release workflow must validate the exact approved API origin from trusted "
                f"main before loading credentials: {relative_path}"
            )
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
        "intentive-desktop-qualification",
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
        *check_codemagic_provider_controls(),
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
