#!/usr/bin/env python3
"""Validate that a signed desktop candidate is eligible for automatic beta qualification."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from desktop_qualification_evidence import REQUIRED_SMOKE_CHECKS, validate_signed_smoke_contract
from desktop_release_metadata import fail, parse_metadata

TAG_RE = re.compile(r"^v(?P<version>\d+\.\d+\.\d+)\+(?P<build>\d+)-macos$")
EXPECTED_BUNDLE_ID = "com.heyintentive.intentive"
EXPECTED_BETA_BUNDLE_ID = "com.heyintentive.intentive.beta"


def load_json(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def asset_by_name(release: dict, names: set[str]) -> dict:
    for asset in release.get("assets", []):
        if asset.get("name") in names:
            return asset
    fail(f"release is missing asset: {', '.join(sorted(names))}")


def smoke_artifact(smoke: dict, label: str) -> dict:
    for artifact in smoke.get("artifacts", []):
        if artifact.get("label") == label:
            return artifact
    fail(f"signed smoke result is missing {label!r} artifact evidence")


def normalized_digest(asset: dict) -> str:
    digest = str(asset.get("digest") or "")
    if not digest.startswith("sha256:"):
        fail(f"release asset {asset.get('name')!r} is missing a SHA-256 digest")
    return digest.removeprefix("sha256:")


def _validate_smoke_contract(
    smoke: dict,
    *,
    bundle_id: str,
    release_tag: str,
    expected_version: str,
    expected_build: str,
    expected_source_sha: str,
    expected_team_id: str,
    label: str,
) -> set[str]:
    """Enforce the shared success/tag/version/build/team/channel contract on a
    smoke result. The beta artifact must satisfy the same bar as stable, only
    with its own bundle id."""
    try:
        return validate_signed_smoke_contract(
            smoke,
            bundle_id=bundle_id,
            release_tag=release_tag,
            expected_version=expected_version,
            expected_build=expected_build,
            expected_source_sha=expected_source_sha,
            expected_team_id=expected_team_id,
            label=label,
        )
    except ValueError as exc:
        fail(str(exc).removeprefix("qualification evidence "))


def validate(args: argparse.Namespace) -> dict:
    qualification_mode = str(getattr(args, "qualification_mode", "runner"))
    if qualification_mode not in {"runner", "owner-manual"}:
        fail("beta qualification mode is invalid")
    expected_team_id = str(getattr(args, "expected_team_id", "")).strip()
    if not re.fullmatch(r"[A-Z0-9]{10}", expected_team_id):
        fail("automatic beta qualification requires the owned 10-character Apple Team ID")

    match = TAG_RE.match(args.release_tag)
    if not match:
        fail(f"invalid macOS release tag: {args.release_tag}")
    if args.release_tag != args.latest_tag:
        fail(f"automatic beta qualification requires newest tag {args.latest_tag}, got {args.release_tag}")
    if args.tag_sha != args.checkout_sha:
        fail("release tag SHA does not match the Codemagic checkout SHA")

    release = load_json(args.release_json)
    smoke = load_json(args.smoke_result)
    smoke_source_sha = smoke.get("source_sha")
    if not isinstance(smoke_source_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", smoke_source_sha):
        fail("signed smoke result is missing an exact source SHA")
    if smoke_source_sha != args.tag_sha:
        fail("signed smoke source SHA does not match the candidate tag")
    if release.get("tagName") != args.release_tag:
        fail("GitHub release tag does not match the requested candidate")
    if release.get("isDraft") or release.get("isPrerelease"):
        fail("automatic beta candidate must be a published non-prerelease GitHub release")
    if not release.get("publishedAt"):
        fail("automatic beta candidate must have a GitHub publication timestamp")

    metadata = parse_metadata(release.get("body") or "")
    if metadata.get("channel") != "candidate" or metadata.get("isLive", "").lower() not in {"false", "0", "no"}:
        fail("automatic beta qualification requires channel: candidate and isLive: false")
    expected_version = match.group("version")
    expected_build = match.group("build")
    checks = _validate_smoke_contract(
        smoke,
        bundle_id=EXPECTED_BUNDLE_ID,
        release_tag=args.release_tag,
        expected_version=expected_version,
        expected_build=expected_build,
        expected_source_sha=args.tag_sha,
        expected_team_id=expected_team_id,
        label="signed",
    )

    callback_canary = smoke.get("notification_callback_canary")

    zip_release = asset_by_name(release, {"Intentive.zip"})
    dmg_release = asset_by_name(release, {"intentive.dmg"})
    zip_smoke = smoke_artifact(smoke, "sparkle_zip")
    dmg_smoke = smoke_artifact(smoke, "dmg")
    artifact_digests = {
        "Intentive.zip": normalized_digest(zip_release),
        dmg_release["name"]: normalized_digest(dmg_release),
    }
    if zip_smoke.get("sha256") != artifact_digests["Intentive.zip"]:
        fail("published Intentive.zip digest does not match the signed artifact smoke")
    if dmg_smoke.get("sha256") != artifact_digests[dmg_release["name"]]:
        fail("published DMG digest does not match the signed artifact smoke")

    # Releases that ship the side-by-side Intentive Beta identity carry a second smoke
    # result; when those assets exist the beta artifact must satisfy the same
    # contract as stable (older releases without beta assets stay valid).
    beta_assets = {a.get("name") for a in release.get("assets", [])}
    if qualification_mode == "owner-manual" and not set(("Intentive.Beta.zip", "intentive-beta.dmg")).issubset(
        beta_assets
    ):
        fail("owner-manual qualification requires exact Intentive Beta ZIP/DMG assets")
    if "Intentive.Beta.zip" in beta_assets:
        if not getattr(args, "beta_smoke_result", "") or not Path(args.beta_smoke_result).exists():
            fail("release ships Intentive Beta assets but no beta smoke result was provided")
        beta_smoke = load_json(args.beta_smoke_result)
        _validate_smoke_contract(
            beta_smoke,
            bundle_id=EXPECTED_BETA_BUNDLE_ID,
            release_tag=args.release_tag,
            expected_version=expected_version,
            expected_build=expected_build,
            expected_source_sha=args.tag_sha,
            expected_team_id=expected_team_id,
            label="beta",
        )
        beta_zip_release = asset_by_name(release, {"Intentive.Beta.zip"})
        beta_dmg_release = asset_by_name(release, {"intentive-beta.dmg"})
        beta_zip_smoke = smoke_artifact(beta_smoke, "sparkle_zip")
        beta_dmg_smoke = smoke_artifact(beta_smoke, "dmg")
        artifact_digests["Intentive.Beta.zip"] = normalized_digest(beta_zip_release)
        artifact_digests["intentive-beta.dmg"] = normalized_digest(beta_dmg_release)
        if beta_zip_smoke.get("sha256") != artifact_digests["Intentive.Beta.zip"]:
            fail("published Intentive.Beta.zip digest does not match the beta artifact smoke")
        if beta_dmg_smoke.get("sha256") != artifact_digests["intentive-beta.dmg"]:
            fail("published intentive-beta.dmg digest does not match the beta artifact smoke")

    return {
        "passed": True,
        "gate": "desktop-auto-beta-candidate-v1",
        "qualification_mode": qualification_mode,
        "release_tag": args.release_tag,
        "source_sha": smoke_source_sha,
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "artifact_digests": artifact_digests,
        "signed_smoke_checks": sorted(checks),
        "notification_callback_canary": callback_canary,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-json", required=True)
    parser.add_argument("--smoke-result", required=True)
    parser.add_argument("--beta-smoke-result", default="")
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--latest-tag", required=True)
    parser.add_argument("--tag-sha", required=True)
    parser.add_argument("--checkout-sha", required=True)
    parser.add_argument("--expected-team-id", required=True)
    parser.add_argument("--qualification-mode", choices=("runner", "owner-manual"), default="runner")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = validate(args)
    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"automatic beta candidate gate passed: {args.release_tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
