#!/usr/bin/env python3
"""Public-contract tests for content-addressed owner-manual evidence."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

import pytest

SCRIPT = Path(__file__).with_name("owner_manual_desktop_qualification.py")
SPEC = importlib.util.spec_from_file_location("owner_manual_desktop_qualification", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

TAG = "v0.12.99+12099-macos"
SHA = "a" * 40
ASSETS = {
    "Intentive.zip": b"stable zip",
    "intentive.dmg": b"stable dmg",
    "Intentive.Beta.zip": b"beta zip",
    "intentive-beta.dmg": b"beta dmg",
}
DIGESTS = {name: hashlib.sha256(value).hexdigest() for name, value in ASSETS.items()}


def _smoke(bundle_id: str, zip_name: str, dmg_name: str) -> dict[str, object]:
    return {
        "ok": True,
        "finished_at": "2026-07-21T12:02:30+00:00",
        "release_tag": TAG,
        "source_sha": SHA,
        "expected_channel": "beta",
        "bundle_id": bundle_id,
        "version": "0.12.99",
        "build": "12099",
        "team_id": "24D6NXS6H7",
        "checks": sorted(MODULE.REQUIRED_SMOKE_CHECKS),
        "notification_callback_canary": {
            "schema": 1,
            "event": "user-notifications-settings-callback-completed",
            "bundle_id": bundle_id,
            "main_actor": True,
            "authorization_status": 2,
            "validated": True,
        },
        "artifacts": [
            {"label": "sparkle_zip", "sha256": DIGESTS[zip_name]},
            {"label": "dmg", "sha256": DIGESTS[dmg_name]},
        ],
    }


def receipts(root: Path) -> dict[str, Path]:
    payloads = {
        "release.json": {
            "tagName": TAG,
            "isDraft": False,
            "isPrerelease": False,
            "publishedAt": "2026-07-21T12:00:00Z",
        },
        "candidate-gate.json": {
            "passed": True,
            "qualification_mode": "owner-manual",
            "release_tag": TAG,
            "source_sha": SHA,
            "artifact_digests": DIGESTS,
            "verified_at": "2026-07-21T12:00:30+00:00",
        },
        "provider-smoke-stable.json": _smoke("com.heyintentive.intentive", "Intentive.zip", "intentive.dmg"),
        "provider-smoke-beta.json": _smoke(
            "com.heyintentive.intentive.beta", "Intentive.Beta.zip", "intentive-beta.dmg"
        ),
        "owner-smoke-stable.json": _smoke("com.heyintentive.intentive", "Intentive.zip", "intentive.dmg"),
        "owner-smoke-beta.json": _smoke("com.heyintentive.intentive.beta", "Intentive.Beta.zip", "intentive-beta.dmg"),
        "pre-tag-readiness.json": {
            "kind": "intentive-desktop-pre-tag-readiness-v1",
            "passed": True,
            "source_sha": SHA,
            "provider_mode": "offline",
            "lane": "local",
            "started_at": "2026-07-21T12:00:40Z",
            "duration_s": 5,
            "checks": {
                name: True
                for name in (
                    "source_resolved_from_origin",
                    "exact_sha_checkout_verified",
                    "runner_self_clean",
                    "swift_cache_prepared",
                    "self_check",
                    "offline_stack_ready",
                )
            },
        },
        "source-t2-manifest.json": {
            "passed": True,
            "tier": 2,
            "provider_mode": "offline",
            "git_sha": SHA,
            "repository_git_sha": SHA,
            "bundle": "omi-qualification-0.12.99+12099",
            "source_provenance": "bundle-health",
            "source_tree_dirty": False,
            "started_at": "2026-07-21T12:01:00Z",
            "duration_s": 5,
        },
        "fault-manifest.json": {
            "passed": True,
            "tier": "fault",
            "provider_mode": "offline",
            "git_sha": SHA,
            "repository_git_sha": SHA,
            "bundle": "omi-fault-test",
            "source_provenance": "bundle-health",
            "source_tree_dirty": False,
            "started_at": "2026-07-21T12:02:00Z",
            "duration_s": 5,
        },
        "backend-compatibility.json": {
            "schema_version": 1,
            "status": "healthy",
            "service": "backend",
            "process_health_status": "ok",
            "chat_contract_version": "1",
        },
    }
    result: dict[str, Path] = {}
    for name, payload in payloads.items():
        path = root / name
        path.write_text(json.dumps(payload), encoding="utf-8")
        result[name] = path
    ledger_receipts = {
        "pre-tag-readiness": "pre-tag-readiness.json",
        "candidate-gate": "candidate-gate.json",
        "stable-signed-smoke": "owner-smoke-stable.json",
        "beta-signed-smoke": "owner-smoke-beta.json",
        "source-t2": "source-t2-manifest.json",
        "fault-suite": "fault-manifest.json",
    }
    ledger_argv = {
        "pre-tag-readiness": ["pre-tag-readiness.sh", TAG],
        "candidate-gate": ["check-desktop-auto-beta-candidate.py", "--qualification-mode", "owner-manual", TAG],
        "stable-signed-smoke": ["smoke-signed-desktop-artifact.sh", "com.heyintentive.intentive", TAG],
        "beta-signed-smoke": ["smoke-signed-desktop-artifact.sh", "com.heyintentive.intentive.beta", TAG],
        "source-t2": ["qualify-desktop-beta.sh", "--automatic", TAG],
        "fault-suite": ["qualify-desktop-beta.sh", "--automatic", TAG],
    }
    ledger = {
        "schema_version": 1,
        "qualification_mode": "owner-manual",
        "release_tag": TAG,
        "source_sha": SHA,
        "commands": [
            {
                "label": label,
                "argv": ledger_argv[label],
                "exit_code": 0,
                "recorded_at": "2026-07-21T12:03:00Z",
                "receipt": receipt,
                "receipt_sha256": hashlib.sha256(result[receipt].read_bytes()).hexdigest(),
            }
            for label, receipt in ledger_receipts.items()
        ],
    }
    ledger_path = root / "command-ledger.json"
    ledger_path.write_text(json.dumps(ledger), encoding="utf-8")
    result[ledger_path.name] = ledger_path
    return result


def test_build_and_verify_binds_every_raw_receipt_and_exact_beta_bytes() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        output = MODULE.build_bundle(receipts(root), root, TAG, SHA)
        assert output.name.startswith(f"owner-manual-qualification-{SHA}-")
        assert output.suffix == ".zip"
        verified = MODULE.verify_bundle(output.read_bytes(), TAG, SHA, DIGESTS)
        assert verified["qualification_mode"] == "owner-manual"
        assert verified["artifact_digests"] == DIGESTS


def test_missing_beta_smoke_or_failing_command_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = receipts(root)
        source.pop("owner-smoke-beta.json")
        with pytest.raises(ValueError, match="exact receipt set"):
            MODULE.build_bundle(source, root, TAG, SHA)

        source = receipts(root)
        ledger = json.loads(source["command-ledger.json"].read_text(encoding="utf-8"))
        ledger["commands"][-1]["exit_code"] = 1
        source["command-ledger.json"].write_text(json.dumps(ledger), encoding="utf-8")
        with pytest.raises(ValueError, match="command ledger"):
            MODULE.build_bundle(source, root, TAG, SHA)


def test_receipt_replacement_and_zip_extra_member_are_rejected() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        output = MODULE.build_bundle(receipts(root), root, TAG, SHA)
        raw = output.read_bytes()
        archive = root / "mutated.zip"
        archive.write_bytes(raw)
        with zipfile.ZipFile(archive, "a") as contents:
            contents.writestr("unexpected.json", b"{}")
        with pytest.raises(ValueError, match="unexpected contents"):
            MODULE.verify_bundle(archive.read_bytes(), TAG, SHA, DIGESTS)

        wrong = dict(DIGESTS)
        wrong["Intentive.Beta.zip"] = "f" * 64
        with pytest.raises(ValueError, match="artifact digests"):
            MODULE.verify_bundle(raw, TAG, SHA, wrong)


@pytest.mark.parametrize("receipt_name", ["source-t2-manifest.json", "fault-manifest.json"])
def test_stale_behavioral_manifest_cannot_be_relabelled_for_a_new_candidate(receipt_name: str) -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = receipts(root)
        payload = json.loads(source[receipt_name].read_text(encoding="utf-8"))
        payload["git_sha"] = "b" * 40
        payload["repository_git_sha"] = "b" * 40
        source[receipt_name].write_text(json.dumps(payload), encoding="utf-8")
        with pytest.raises(ValueError, match="T2 receipt|fault-suite receipt"):
            MODULE.build_bundle(source, root, TAG, SHA)


def test_ledger_hash_and_full_signed_smoke_contract_cannot_be_relabelled() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = receipts(root)
        smoke = json.loads(source["owner-smoke-beta.json"].read_text(encoding="utf-8"))
        smoke["checks"] = []
        source["owner-smoke-beta.json"].write_text(json.dumps(smoke), encoding="utf-8")
        ledger = json.loads(source["command-ledger.json"].read_text(encoding="utf-8"))
        beta_entry = next(entry for entry in ledger["commands"] if entry["label"] == "beta-signed-smoke")
        beta_entry["receipt_sha256"] = hashlib.sha256(source["owner-smoke-beta.json"].read_bytes()).hexdigest()
        source["command-ledger.json"].write_text(json.dumps(ledger), encoding="utf-8")
        with pytest.raises(ValueError, match="signed-smoke receipt"):
            MODULE.build_bundle(source, root, TAG, SHA)


def test_ledger_timestamp_must_follow_the_exact_receipt_outcome() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = receipts(root)
        ledger = json.loads(source["command-ledger.json"].read_text(encoding="utf-8"))
        beta_entry = next(entry for entry in ledger["commands"] if entry["label"] == "beta-signed-smoke")
        beta_entry["recorded_at"] = "2026-07-21T12:02:00Z"
        source["command-ledger.json"].write_text(json.dumps(ledger), encoding="utf-8")

        with pytest.raises(ValueError, match="timestamp predates"):
            MODULE.build_bundle(source, root, TAG, SHA)


def test_repository_local_collector_packages_a_prepared_stage_through_the_public_cli() -> None:
    collector = Path(__file__).parents[2] / "desktop/macos/scripts/collect-owner-manual-beta-qualification.sh"
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        stage = root / "stage"
        output = root / "output"
        stage.mkdir()
        receipts(stage)
        result = subprocess.run(
            [
                "bash",
                str(collector),
                "--prepared-stage",
                str(stage),
                "--source-sha",
                SHA,
                "--output-directory",
                str(output),
                TAG,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stderr
        bundles = list(output.glob(f"owner-manual-qualification-{SHA}-*.zip"))
        assert len(bundles) == 1
        MODULE.verify_bundle(bundles[0].read_bytes(), TAG, SHA, DIGESTS)

        source = receipts(root)
        ledger = json.loads(source["command-ledger.json"].read_text(encoding="utf-8"))
        ledger["commands"][0]["receipt_sha256"] = "f" * 64
        source["command-ledger.json"].write_text(json.dumps(ledger), encoding="utf-8")
        with pytest.raises(ValueError, match="bind its receipt bytes"):
            MODULE.build_bundle(source, root, TAG, SHA)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
