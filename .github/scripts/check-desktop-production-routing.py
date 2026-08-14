#!/usr/bin/env python3
"""Fail closed when a production-family macOS client can leave its data plane."""

from __future__ import annotations

import re
from pathlib import Path

RETIRED_GKE_DESKTOP_BACKEND_CHART_ROOTS = ("backend/charts", "desktop/macos/charts")
RETIRED_GKE_DESKTOP_BACKEND_MANIFEST_SUFFIXES = {".tpl", ".yaml", ".yml"}
RETIRED_GKE_DESKTOP_BACKEND_MARKERS = ("desktop-api.omi.me", "desktop-backend")
GKE_WORKFLOW_MARKERS = ("gcloud container clusters", "helm ", "kubectl ")
DESKTOP_BACKEND_ENVIRONMENT_PATH = "desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift"
FORBIDDEN_ROUTING_TOKENS = ("OMI_BETA_RELEASE_RING", "api-beta.omi.me", "STAGING_API_URL")
REQUIRED_PRODUCTION_FRAGMENTS = {
    "desktop/macos/Desktop/Sources/AppBuild.swift": (
        'productionBundleIdentifier = "com.omi.computer-macos"',
        "externalPreviewBundleIdentifierPrefix",
    ),
    "desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift": (
        'productionPythonAPIURL = "https://api.omi.me/"',
        'productionRustBackendURL = "https://desktop-backend-hhibjajaja-uc.a.run.app/"',
    ),
    "desktop/macos/Desktop/Sources/GoogleService-Info.plist": ("<string>based-hardware</string>",),
}
CANONICAL_BUNDLE_IDENTIFIER = "com.omi.computer-macos"
SANCTIONED_PRODUCTION_BUNDLE_IDENTIFIERS = {
    CANONICAL_BUNDLE_IDENTIFIER,
    "com.omi.computer-macos.beta",
}
BUNDLE_IDENTIFIER_PATTERN = re.compile(r'"(com\.omi\.computer-macos(?:\.[^"]+)?)"')


def _is_windows_only_workflow(path: Path) -> bool:
    return "windows" in path.stem.lower()


def _retired_gke_desktop_backend_manifests(root: Path) -> list[Path]:
    retired: list[Path] = []
    for relative_root in RETIRED_GKE_DESKTOP_BACKEND_CHART_ROOTS:
        chart_root = root / relative_root
        if not chart_root.is_dir():
            continue
        for manifest in chart_root.rglob("*"):
            if not manifest.is_file() or manifest.suffix not in RETIRED_GKE_DESKTOP_BACKEND_MANIFEST_SUFFIXES:
                continue
            source = manifest.read_text(encoding="utf-8")
            if any(marker in source for marker in RETIRED_GKE_DESKTOP_BACKEND_MARKERS):
                retired.append(manifest.relative_to(root))

    workflow_root = root / ".github/workflows"
    if workflow_root.is_dir():
        for workflow in workflow_root.glob("*.y*ml"):
            if _is_windows_only_workflow(workflow):
                continue
            source = workflow.read_text(encoding="utf-8")
            if any(marker in source for marker in RETIRED_GKE_DESKTOP_BACKEND_MARKERS) and any(
                marker in source for marker in GKE_WORKFLOW_MARKERS
            ):
                retired.append(workflow.relative_to(root))
    return retired


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    for manifest in _retired_gke_desktop_backend_manifests(root):
        errors.append(
            f"{manifest} declares retired GKE desktop-backend ownership; production desktop-backend is Cloud Run"
        )

    routing_path = root / DESKTOP_BACKEND_ENVIRONMENT_PATH
    if not routing_path.is_file():
        errors.append(f"missing protected production-routing source {DESKTOP_BACKEND_ENVIRONMENT_PATH}")
    else:
        routing_source = routing_path.read_text(encoding="utf-8")
        for token in FORBIDDEN_ROUTING_TOKENS:
            if token in routing_source:
                errors.append(f"{DESKTOP_BACKEND_ENVIRONMENT_PATH} must not contain legacy routing token {token}")

    for relative_path, required_fragments in REQUIRED_PRODUCTION_FRAGMENTS.items():
        source_path = root / relative_path
        if not source_path.is_file():
            errors.append(f"missing protected production identity source {relative_path}")
            continue
        source = source_path.read_text(encoding="utf-8")
        for fragment in required_fragments:
            if fragment not in source:
                errors.append(f"{relative_path} must retain protected production identity fragment {fragment!r}")
        if relative_path.endswith("/AppBuild.swift"):
            for bundle_identifier in BUNDLE_IDENTIFIER_PATTERN.findall(source):
                if bundle_identifier not in SANCTIONED_PRODUCTION_BUNDLE_IDENTIFIERS:
                    errors.append(
                        f"{relative_path} must not define divergent production-family bundle identity "
                        f"{bundle_identifier!r}"
                    )
    return errors


if __name__ == "__main__":
    raise SystemExit(1 if validate(Path(".")) else 0)
