#!/usr/bin/env python3
"""Build and verify immutable trusted desktop qualification evidence.

The evidence is uploaded as a GitHub Actions artifact by the trusted
qualification run.  Its run ID is the authority boundary: promotion verifies
that run came from this workflow on main and then compares freshly downloaded
release bytes with this document.  GitHub release bodies/assets are never the
qualification authority.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
from typing import Any

ARTIFACTS = ("Intentive.zip", "intentive.dmg")
# INV-BETA-1: releases that ship the side-by-side Intentive Beta identity carry two
# additional qualified artifacts; older single-identity releases remain valid.
BETA_ARTIFACTS = ("Intentive.Beta.zip", "intentive-beta.dmg")
ZIP_SIGNATURES = {"Intentive.zip": "edSignature", "Intentive.Beta.zip": "betaEdSignature"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
OWNER_MANUAL_ASSET_RE = re.compile(
    r"^owner-manual-qualification-(?P<source_sha>[0-9a-f]{40})-(?P<digest>[0-9a-f]{64})[.]zip$"
)
UTC_RFC3339_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:[.][0-9]{1,6})?Z$")
OWNER_LOGIN = "sruj75"
OWNER_ID = 120443863
REQUIRED_SMOKE_CHECKS = frozenset(
    {
        "Launch + identity metadata is aligned",
        "Auth persistence prerequisites: signing identity and Keychain-compatible entitlements are sane",
        "Backend routing config matches the declared external backend",
        "Sparkle/update metadata and authoritative ZIP artifacts are present",
        "Native helper/runtime bundle integrity passed",
        "Local storage/database package surface is present",
        "Signed artifact Keychain write/read/delete canary passed",
        "UserNotifications settings callback completion canary passed",
        "Signed desktop artifact smoke completed",
    }
)


def _fail(message: str) -> None:
    raise ValueError(f"qualification evidence {message}")


def _metadata(body: str) -> dict[str, str]:
    match = re.search(r"KEY_VALUE_START\s*(.*?)\s*KEY_VALUE_END", body, re.DOTALL)
    if not match:
        return {}
    return {
        key.strip(): value.strip()
        for key, value in (line.split(":", 1) for line in match.group(1).splitlines() if ":" in line)
    }


def _asset(release: dict[str, Any], name: str) -> dict[str, Any]:
    matches = [item for item in release.get("assets", []) if item.get("name") == name]
    if len(matches) != 1:
        _fail(f"requires exactly one {name} asset")
    return matches[0]


def _url(asset: dict[str, Any]) -> str:
    value = asset.get("url") or asset.get("browser_download_url")
    if not isinstance(value, str) or not value.startswith("https://"):
        _fail("contains an invalid asset URL")
    return value


def validate_signed_smoke_contract(
    smoke: dict[str, Any],
    *,
    bundle_id: str,
    release_tag: str,
    expected_version: str,
    expected_build: str,
    expected_source_sha: str,
    expected_team_id: str,
    label: str,
) -> set[str]:
    expected = {
        "ok": True,
        "release_tag": release_tag,
        "expected_channel": "beta",
        "bundle_id": bundle_id,
        "version": expected_version,
        "build": expected_build,
        "team_id": expected_team_id,
    }
    for field, value in expected.items():
        if smoke.get(field) != value:
            _fail(f"{label} smoke result {field} mismatch")
    if (
        smoke.get("source_sha") != expected_source_sha
        or re.fullmatch(r"[0-9a-f]{40}", str(smoke.get("source_sha") or "")) is None
    ):
        _fail(f"{label} smoke source SHA does not match the candidate tag")
    raw_checks = smoke.get("checks")
    if not isinstance(raw_checks, list) or any(not isinstance(item, str) for item in raw_checks):
        _fail(f"{label} smoke result checks are invalid")
    checks = set(raw_checks)
    missing = sorted(REQUIRED_SMOKE_CHECKS - checks)
    if missing:
        _fail(f"{label} smoke result is missing required checks: {', '.join(missing)}")
    canary = smoke.get("notification_callback_canary")
    expected_canary = {
        "schema": 1,
        "event": "user-notifications-settings-callback-completed",
        "bundle_id": bundle_id,
        "main_actor": True,
        "validated": True,
    }
    if not isinstance(canary, dict):
        _fail(f"{label} smoke result is missing UserNotifications callback canary evidence")
    for field, value in expected_canary.items():
        if canary.get(field) != value:
            _fail(f"{label} smoke UserNotifications callback canary {field} mismatch")
    if not isinstance(canary.get("authorization_status"), int) or isinstance(canary.get("authorization_status"), bool):
        _fail(f"{label} smoke UserNotifications callback canary is missing authorization status")
    return checks


def file_sha256(path: Path) -> str:
    return hashlib.file_digest(path.open("rb"), "sha256").hexdigest()


def validate_owner_manual(owner_manual: object, release_tag: str, source_sha: str) -> dict[str, Any]:
    if not isinstance(owner_manual, dict):
        _fail("does not contain typed owner-manual evidence identity")
    asset_name = owner_manual.get("asset_name")
    match = OWNER_MANUAL_ASSET_RE.fullmatch(asset_name) if isinstance(asset_name, str) else None
    expected_url = f"https://github.com/sruj75/knowledge-athlete/releases/download/{release_tag}/{asset_name}"
    encoded_url = expected_url.replace(release_tag, release_tag.replace("+", "%2B"))
    if (
        owner_manual.get("schema_version") != 1
        or match is None
        or match.group("source_sha") != source_sha
        or owner_manual.get("sha256") != match.group("digest")
        or not isinstance(owner_manual.get("asset_id"), int)
        or isinstance(owner_manual.get("asset_id"), bool)
        or owner_manual["asset_id"] <= 0
        or owner_manual.get("asset_url") not in {expected_url, encoded_url}
        or owner_manual.get("uploader_login") != OWNER_LOGIN
        or owner_manual.get("uploader_id") != OWNER_ID
        or not isinstance(owner_manual.get("release_id"), int)
        or isinstance(owner_manual.get("release_id"), bool)
        or owner_manual["release_id"] <= 0
        or not isinstance(owner_manual.get("created_at"), str)
        or UTC_RFC3339_RE.fullmatch(owner_manual["created_at"]) is None
        or set(owner_manual)
        != {
            "schema_version",
            "asset_name",
            "asset_id",
            "asset_url",
            "sha256",
            "uploader_login",
            "uploader_id",
            "release_id",
            "created_at",
        }
    ):
        _fail("contains invalid owner-manual evidence identity")
    return dict(owner_manual)


def build_evidence(
    release: dict[str, Any],
    release_tag: str,
    source_sha: str,
    files: dict[str, Path],
    qualification_run_id: int | None = None,
    *,
    qualification_mode: str = "runner",
    owner_manual: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if release.get("tagName") != release_tag:
        _fail("release ID does not match requested tag")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        _fail("source SHA is not an exact 40-character SHA")
    gate = files.pop("__candidate_gate__")
    candidate_gate = json.loads(gate.read_text(encoding="utf-8"))
    if (
        candidate_gate.get("passed") is not True
        or candidate_gate.get("release_tag") != release_tag
        or candidate_gate.get("source_sha") != source_sha
    ):
        _fail("was not created after the passing candidate gate")
    if qualification_mode not in {"runner", "owner-manual"}:
        _fail("contains an invalid qualification mode")
    if qualification_mode == "owner-manual" and candidate_gate.get("qualification_mode") != "owner-manual":
        _fail("owner-manual evidence was not created after an owner-manual candidate gate")
    metadata = _metadata(str(release.get("body") or ""))
    artifacts: dict[str, dict[str, str]] = {}
    required = {"Intentive.zip", "intentive.dmg"}
    with_beta = required | set(BETA_ARTIFACTS)
    if set(files) not in (required, with_beta):
        _fail(
            "does not contain the exact qualified Intentive.zip and intentive.dmg (plus both beta artifacts when present)"
        )
    if qualification_mode == "owner-manual" and set(files) != with_beta:
        _fail("owner-manual mode requires exact Intentive Beta ZIP/DMG artifacts")
    for name, path in files.items():
        if not path.is_file():
            _fail(f"is missing downloaded {name}")
        asset = _asset(release, name)
        digest = file_sha256(path)
        published = str(asset.get("digest") or "").removeprefix("sha256:")
        if published and published != digest:
            _fail(f"{name} differs from its published candidate digest")
        item = {"url": _url(asset), "sha256": digest}
        signature_key = ZIP_SIGNATURES.get(name)
        if signature_key:
            signature = metadata.get(signature_key, "")
            if not signature:
                _fail(f"is missing {signature_key}")
            item["signature"] = signature
        artifacts[name] = item
    evidence = {
        "schema_version": 1,
        "qualification_mode": qualification_mode,
        "release_id": release_tag,
        "source_sha": source_sha,
        "source_qualification": {
            "passed": True,
            "tier": "T2",
            "subject": "source-built named-bundle",
            "fault_evidence": (
                "owner-manual content-addressed receipts"
                if qualification_mode == "owner-manual"
                else "trusted qualification runner"
            ),
        },
        "signed_artifact_verification": {
            "passed": True,
            "subject": "exact signed ZIP/DMG bytes",
            "checks": ["sha256", "Sparkle signature", "notarization", "signed smoke"],
        },
        "artifacts": artifacts,
    }
    if qualification_run_id is not None:
        if qualification_run_id <= 0:
            _fail("has an invalid qualification run identity")
        evidence["qualification_run_id"] = qualification_run_id
    if qualification_mode == "owner-manual":
        evidence["owner_manual"] = validate_owner_manual(owner_manual, release_tag, source_sha)
    elif owner_manual is not None:
        _fail("runner evidence must not contain owner-manual fields")
    return evidence


def verify_evidence(
    evidence: dict[str, Any], release: dict[str, Any], release_tag: str, source_sha: str, digests: dict[str, str]
) -> None:
    if (
        evidence.get("schema_version") != 1
        or evidence.get("release_id") != release_tag
        or evidence.get("source_sha") != source_sha
    ):
        _fail("release ID or source SHA does not match the trusted run")
    qualification_mode = evidence.get("qualification_mode", "runner")
    if qualification_mode not in {"runner", "owner-manual"}:
        _fail("contains an invalid qualification mode")
    if qualification_mode == "owner-manual":
        validate_owner_manual(evidence.get("owner_manual"), release_tag, source_sha)
        if set(digests) != set(ARTIFACTS) | set(BETA_ARTIFACTS):
            _fail("owner-manual mode requires exact Intentive Beta ZIP/DMG artifacts")
    elif "owner_manual" in evidence:
        _fail("runner evidence must not contain owner-manual fields")
    source_qualification = evidence.get("source_qualification")
    signed_artifacts = evidence.get("signed_artifact_verification")
    if (
        not isinstance(source_qualification, dict)
        or source_qualification.get("passed") is not True
        or source_qualification.get("tier") != "T2"
    ):
        _fail("does not prove source-built named-bundle T2 qualification")
    if not isinstance(signed_artifacts, dict) or signed_artifacts.get("passed") is not True:
        _fail("does not prove exact signed artifact verification")
    if signed_artifacts.get("subject") != "exact signed ZIP/DMG bytes":
        _fail("must not claim signed production bytes ran T2")
    artifacts = evidence.get("artifacts")
    if not isinstance(artifacts, dict):
        _fail("does not contain artifacts")
    metadata = _metadata(str(release.get("body") or ""))
    expected_names = set(digests)
    if set(artifacts) != expected_names:
        _fail("artifact set differs from the downloaded release")
    for name, actual_sha in digests.items():
        item = artifacts.get(name)
        if not isinstance(item, dict) or item.get("sha256") != actual_sha or not SHA256_RE.fullmatch(actual_sha):
            _fail(f"{name} hash differs from trusted evidence")
        if item.get("url") != _url(_asset(release, name)):
            _fail(f"{name} URL differs from trusted evidence")
        signature_key = ZIP_SIGNATURES.get(name)
        if signature_key and item.get("signature") != metadata.get(signature_key):
            _fail(f"{name} signature differs from trusted evidence")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("build", "verify"))
    parser.add_argument("--release-json", required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--candidate-gate")
    parser.add_argument("--qualification-run-id", type=int)
    parser.add_argument("--qualification-mode", choices=("runner", "owner-manual"), default="runner")
    parser.add_argument("--owner-manual-json")
    parser.add_argument("--asset", action="append", default=[])
    args = parser.parse_args()
    release = json.loads(Path(args.release_json).read_text(encoding="utf-8"))
    files: dict[str, Path] = {}
    for raw in args.asset:
        name, sep, path = raw.partition("=")
        if not sep or name not in (*ARTIFACTS, *BETA_ARTIFACTS):
            raise SystemExit("--asset must be NAME=PATH for a qualified release artifact")
        files[name] = Path(path)
    if args.command == "build":
        if not args.candidate_gate:
            raise SystemExit("build requires --candidate-gate")
        files["__candidate_gate__"] = Path(args.candidate_gate)
        owner_manual = (
            json.loads(Path(args.owner_manual_json).read_text(encoding="utf-8")) if args.owner_manual_json else None
        )
        result = build_evidence(
            release,
            args.release_tag,
            args.source_sha,
            files,
            args.qualification_run_id,
            qualification_mode=args.qualification_mode,
            owner_manual=owner_manual,
        )
        Path(args.evidence).write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    else:
        evidence = json.loads(Path(args.evidence).read_text(encoding="utf-8"))
        verify_evidence(
            evidence,
            release,
            args.release_tag,
            args.source_sha,
            {name: file_sha256(path) for name, path in files.items()},
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
