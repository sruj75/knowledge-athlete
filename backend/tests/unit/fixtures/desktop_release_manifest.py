"""Test-only builders for canonical desktop release manifest payloads."""

from typing import Any


def make_desktop_release_manifest(**overrides: Any) -> dict[str, Any]:
    """Return a fresh valid app-only v1 manifest with optional top-level overrides."""
    manifest: dict[str, Any] = {
        "schema_version": 1,
        "release_id": "v0.12.64+12064-macos",
        "platform": "macos",
        "version": "0.12.64",
        "build_number": 12064,
        "app_source_sha": "a" * 40,
        "zip_url": "https://github.com/sruj75/knowledge-athlete/releases/download/v0.12.64+12064-macos/Intentive.zip",
        "dmg_url": "https://github.com/sruj75/knowledge-athlete/releases/download/v0.12.64+12064-macos/intentive.dmg",
        "ed_signature": "sparkle-signature",
        "qualification_evidence_asset": "qualification-evidence-v0.12.64+12064-macos.json",
        "qualification_evidence_sha256": "sha256:" + "d" * 64,
        "qualification_tier": "T2",
        "qualification_passed": True,
        "created_at": "2026-07-09T12:00:00Z",
        "published_at": "2026-07-09T12:00:00Z",
        "changelog": ["Qualified beta"],
        "mandatory": False,
        "zip_sha256": "sha256:" + "b" * 64,
        "dmg_sha256": "sha256:" + "c" * 64,
    }
    manifest.update(overrides)
    return manifest
