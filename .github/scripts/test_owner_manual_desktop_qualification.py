#!/usr/bin/env python3
"""Public-contract tests for content-addressed owner-manual evidence."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
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
            "chat_contract_version": "2",
        },
    }
    result: dict[str, Path] = {}
    for name, payload in payloads.items():
        path = root / name
        path.write_text(json.dumps(payload), encoding="utf-8")
        result[name] = path
    ledger_argv = {
        "candidate-gate": [
            "python3",
            "check-desktop-auto-beta-candidate.py",
            "--qualification-mode",
            "owner-manual",
            "--release-tag",
            TAG,
            "--tag-sha",
            SHA,
            "--checkout-sha",
            SHA,
            "--expected-team-id",
            "24D6NXS6H7",
        ],
        "stable-signed-smoke": [
            "smoke-signed-desktop-artifact.sh",
            "--expected-bundle-id",
            "com.heyintentive.intentive",
            "--tag",
            TAG,
            "--source-sha",
            SHA,
            "--expected-channel",
            "beta",
            "--launch",
            "--auth-storage-canary",
            "--notification-callback-canary",
        ],
        "beta-signed-smoke": [
            "smoke-signed-desktop-artifact.sh",
            "--expected-bundle-id",
            "com.heyintentive.intentive.beta",
            "--tag",
            TAG,
            "--source-sha",
            SHA,
            "--expected-channel",
            "beta",
            "--launch",
            "--auth-storage-canary",
            "--notification-callback-canary",
        ],
        "pre-tag-readiness": ["pre-tag-readiness.sh", SHA],
        "source-qualification": [
            "qualify-desktop-beta.sh",
            "--automatic",
            "--signed-smoke-result",
            "provider-smoke-stable.json",
            "--candidate-gate-result",
            "candidate-gate.json",
            "--local-evidence-directory",
            "<private-stage>",
            TAG,
        ],
        "backend-compatibility": [
            "python3",
            "owner_manual_desktop_qualification.py",
            "verify-backend-compatibility",
            "--backend-contract-source",
            "desktop_core.py",
            "--process-health",
            "backend-health.json",
            "--root-health",
            "backend-root.json",
            "--output",
            "backend-compatibility.json",
        ],
    }
    ledger_receipts = {
        "candidate-gate": ["candidate-gate.json"],
        "stable-signed-smoke": ["owner-smoke-stable.json"],
        "beta-signed-smoke": ["owner-smoke-beta.json"],
        "pre-tag-readiness": ["pre-tag-readiness.json"],
        "source-qualification": ["source-t2-manifest.json", "fault-manifest.json"],
        "backend-compatibility": ["backend-compatibility.json"],
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
                "started_at": "2026-07-21T12:00:01Z",
                "finished_at": "2026-07-21T12:05:00Z",
                "receipts": [
                    {
                        "name": receipt,
                        "sha256": hashlib.sha256(result[receipt].read_bytes()).hexdigest(),
                    }
                    for receipt in receipt_names
                ],
            }
            for label, receipt_names in ledger_receipts.items()
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
        beta_entry["receipts"][0]["sha256"] = hashlib.sha256(source["owner-smoke-beta.json"].read_bytes()).hexdigest()
        source["command-ledger.json"].write_text(json.dumps(ledger), encoding="utf-8")
        with pytest.raises(ValueError, match="signed-smoke receipt"):
            MODULE.build_bundle(source, root, TAG, SHA)


def test_ledger_timestamp_must_follow_the_exact_receipt_outcome() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = receipts(root)
        ledger = json.loads(source["command-ledger.json"].read_text(encoding="utf-8"))
        beta_entry = next(entry for entry in ledger["commands"] if entry["label"] == "beta-signed-smoke")
        beta_entry["finished_at"] = "2026-07-21T12:02:00Z"
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
        ledger["commands"][0]["receipts"][0]["sha256"] = "f" * 64
        source["command-ledger.json"].write_text(json.dumps(ledger), encoding="utf-8")
        with pytest.raises(ValueError, match="bind its receipt bytes"):
            MODULE.build_bundle(source, root, TAG, SHA)


def test_backend_compatibility_uses_the_backend_owned_contract_version() -> None:
    backend_contract = Path(__file__).parents[2] / "backend/routers/desktop_core.py"
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        process_health = root / "process.json"
        compatibility = root / "compatibility.json"
        output = root / "result.json"
        process_health.write_text('{"status":"ok"}', encoding="utf-8")
        compatibility.write_text(
            '{"status":"healthy","service":"backend","chat_contract_version":"2"}',
            encoding="utf-8",
        )
        result = MODULE.validate_backend_compatibility(backend_contract, process_health, compatibility, output)
        assert result["chat_contract_version"] == "2"
        assert json.loads(output.read_text(encoding="utf-8")) == result

        compatibility.write_text(
            '{"status":"healthy","service":"backend","chat_contract_version":"1"}',
            encoding="utf-8",
        )
        with pytest.raises(ValueError, match="backend compatibility"):
            MODULE.validate_backend_compatibility(backend_contract, process_health, compatibility, output)


def test_bundle_verifier_resolves_the_backend_contract_from_the_runtime_image_layout() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        runtime = root / "app"
        runtime.mkdir()
        contract_path = runtime / "owner_manual_desktop_qualification_contract.py"
        for source in (
            Path(__file__).with_name("owner_manual_desktop_qualification.py"),
            Path(__file__).with_name("desktop_qualification_evidence.py"),
            Path(__file__).with_name("verify-pre-tag-readiness.py"),
        ):
            shutil.copy2(
                source, runtime / (contract_path.name if source.name.startswith("owner_manual") else source.name)
            )
        backend_contract = runtime / "routers/desktop_core.py"
        backend_contract.parent.mkdir()
        shutil.copy2(Path(__file__).parents[2] / "backend/routers/desktop_core.py", backend_contract)
        spec = importlib.util.spec_from_file_location("runtime_owner_manual_contract", contract_path)
        assert spec and spec.loader
        runtime_contract = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runtime_contract)
        receipt_root = root / "receipts"
        receipt_root.mkdir()
        output = runtime_contract.build_bundle(receipts(receipt_root), root / "output", TAG, SHA)
        verified = runtime_contract.verify_bundle(output.read_bytes(), TAG, SHA, DIGESTS)
        assert verified["source_sha"] == SHA


def _write_executable(path: Path, source: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def test_collector_invokes_both_signed_smokes_with_notification_callback_canary() -> None:
    collector_source = Path(__file__).parents[2] / "desktop/macos/scripts/collect-owner-manual-beta-qualification.sh"
    contract_sources = [
        Path(__file__).with_name("owner_manual_desktop_qualification.py"),
        Path(__file__).with_name("desktop_qualification_evidence.py"),
        Path(__file__).with_name("verify-pre-tag-readiness.py"),
    ]
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        repo = root / "repo"
        scripts = repo / "desktop/macos/scripts"
        github_scripts = repo / ".github/scripts"
        scripts.mkdir(parents=True)
        github_scripts.mkdir(parents=True)
        collector = scripts / collector_source.name
        shutil.copy2(collector_source, collector)
        for source in contract_sources:
            shutil.copy2(source, github_scripts / source.name)
        backend_contract = repo / "backend/routers/desktop_core.py"
        backend_contract.parent.mkdir(parents=True)
        shutil.copy2(Path(__file__).parents[2] / "backend/routers/desktop_core.py", backend_contract)
        receipt_fixtures = root / "receipt-fixtures"
        receipt_fixtures.mkdir()
        receipts(receipt_fixtures)
        smoke_log = root / "smoke-invocations.jsonl"
        _write_executable(
            github_scripts / "check-desktop-auto-beta-candidate.py",
            """#!/usr/bin/env python3
from datetime import datetime, timezone
import json, os, sys
args = sys.argv[1:]
target = args[args.index('--output') + 1]
payload = json.load(open(os.path.join(os.environ['FAKE_RECEIPTS'], 'candidate-gate.json'), encoding='utf-8'))
payload['verified_at'] = datetime.now(timezone.utc).isoformat()
json.dump(payload, open(target, 'w', encoding='utf-8'))
""",
        )
        _write_executable(
            scripts / "smoke-signed-desktop-artifact.sh",
            """#!/usr/bin/env python3
from datetime import datetime, timezone
import json, os, sys
args = sys.argv[1:]
with open(os.environ['FAKE_SMOKE_LOG'], 'a', encoding='utf-8') as stream:
    stream.write(json.dumps(args) + '\\n')
target = args[args.index('--result-json') + 1]
bundle_id = args[args.index('--expected-bundle-id') + 1]
name = 'owner-smoke-beta.json' if bundle_id.endswith('.beta') else 'owner-smoke-stable.json'
payload = json.load(open(os.path.join(os.environ['FAKE_RECEIPTS'], name), encoding='utf-8'))
payload['finished_at'] = datetime.now(timezone.utc).isoformat()
json.dump(payload, open(target, 'w', encoding='utf-8'))
""",
        )
        _write_executable(
            scripts / "pre-tag-readiness.sh",
            """#!/usr/bin/env python3
from datetime import datetime, timezone
import json, os, sys
args = sys.argv[1:]
target = args[args.index('--evidence') + 1]
payload = json.load(open(os.path.join(os.environ['FAKE_RECEIPTS'], 'pre-tag-readiness.json'), encoding='utf-8'))
payload['started_at'] = datetime.now(timezone.utc).isoformat()
payload['duration_s'] = 0
json.dump(payload, open(target, 'w', encoding='utf-8'))
raise SystemExit(int(os.environ.get('FAKE_READINESS_EXIT_CODE', '0')))
""",
        )
        _write_executable(
            scripts / "qualify-desktop-beta.sh",
            """#!/usr/bin/env python3
from datetime import datetime, timezone
import json, os, sys
args = sys.argv[1:]
stage = args[args.index('--local-evidence-directory') + 1]
for name in ('source-t2-manifest.json', 'fault-manifest.json'):
    payload = json.load(open(os.path.join(os.environ['FAKE_RECEIPTS'], name), encoding='utf-8'))
    payload['started_at'] = datetime.now(timezone.utc).isoformat()
    payload['duration_s'] = 0
    json.dump(payload, open(os.path.join(stage, name), 'w', encoding='utf-8'))
""",
        )
        bin_dir = root / "bin"
        _write_executable(
            bin_dir / "git",
            f"""#!/usr/bin/env bash
case "$*" in
  *"rev-parse {TAG}^{{commit}}"*|*"rev-parse HEAD"*) echo {SHA} ;;
  *"status --porcelain"*) ;;
  *"for-each-ref"*) echo {TAG} ;;
  *) exit 88 ;;
esac
""",
        )
        _write_executable(bin_dir / "uname", "#!/usr/bin/env bash\necho Darwin\n")
        _write_executable(
            bin_dir / "gh",
            """#!/usr/bin/env python3
from pathlib import Path
import json, os, sys
args = sys.argv[1:]
if args[:2] == ['release', 'view']:
    print(Path(os.environ['FAKE_RECEIPTS'], 'release.json').read_text(encoding='utf-8'))
elif args[:2] == ['release', 'download']:
    destination = Path(args[args.index('--dir') + 1])
    destination.mkdir(parents=True, exist_ok=True)
    for index, value in enumerate(args):
        if value == '--pattern':
            name = args[index + 1]
            fixture_name = {
                'desktop-smoke-result.json': 'provider-smoke-stable.json',
                'desktop-smoke-result-beta.json': 'provider-smoke-beta.json',
            }.get(name, name)
            fixture = Path(os.environ['FAKE_RECEIPTS'], fixture_name)
            if fixture.is_file():
                (destination / name).write_bytes(fixture.read_bytes())
            else:
                (destination / name).write_bytes(name.encode())
else:
    raise SystemExit(87)
""",
        )
        _write_executable(
            bin_dir / "curl",
            """#!/usr/bin/env python3
import sys
url = sys.argv[-1]
if url.endswith('/v1/health'):
    print('{"status":"ok"}')
else:
    print('{"status":"healthy","service":"backend","version":"0.1.0","chat_contract_version":"2"}')
""",
        )
        env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "TMPDIR": str(root / "tmp"),
            "FAKE_RECEIPTS": str(receipt_fixtures),
            "FAKE_SMOKE_LOG": str(smoke_log),
            "OMI_SIGNED_ARTIFACT_SMOKE_TEAM_ID": "24D6NXS6H7",
            "INTENTIVE_STABLE_FEED_URL": "https://updates.example.test/stable.xml",
            "INTENTIVE_BETA_FEED_URL": "https://updates.example.test/beta.xml",
            "INTENTIVE_MANUAL_DOWNLOAD_URL": "https://download.example.test/",
            "INTENTIVE_PRODUCTION_API_URL": "https://api.example.test/",
            "POSTHOG_PROJECT_API_KEY": "public-project-token",
            "POSTHOG_HOST": "https://analytics.example.test/",
            "INTENTIVE_PRODUCT_URL": "https://product.example.test/",
            "INTENTIVE_TERMS_URL": "https://terms.example.test/",
            "INTENTIVE_PRIVACY_URL": "https://privacy.example.test/",
            "INTENTIVE_SUPPORT_URL": "https://support.example.test/",
        }
        (root / "tmp").mkdir()
        result = subprocess.run(
            ["bash", str(collector), "--output-directory", str(root / "output"), TAG],
            cwd=repo,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stderr
        invocations = [json.loads(line) for line in smoke_log.read_text(encoding="utf-8").splitlines()]
        assert len(invocations) == 2
        assert all("--notification-callback-canary" in invocation for invocation in invocations)
        bundles = list((root / "output").glob(f"owner-manual-qualification-{SHA}-*.zip"))
        assert len(bundles) == 1
        with zipfile.ZipFile(bundles[0]) as archive:
            ledger = json.loads(archive.read("command-ledger.json"))
        assert [command["label"] for command in ledger["commands"]] == [
            "candidate-gate",
            "stable-signed-smoke",
            "beta-signed-smoke",
            "pre-tag-readiness",
            "source-qualification",
            "backend-compatibility",
        ]
        source_command = ledger["commands"][4]
        assert source_command["exit_code"] == 0
        assert source_command["started_at"] < source_command["finished_at"]
        assert [receipt["name"] for receipt in source_command["receipts"]] == [
            "source-t2-manifest.json",
            "fault-manifest.json",
        ]
        assert TAG in source_command["argv"]

        failed = subprocess.run(
            ["bash", str(collector), "--output-directory", str(root / "failed-output"), TAG],
            cwd=repo,
            env={**env, "FAKE_READINESS_EXIT_CODE": "17"},
            check=False,
            capture_output=True,
            text=True,
        )
        assert failed.returncode == 17
        match = re.search(r"retained scoped evidence at (.+)", failed.stderr)
        assert match is not None
        failed_stage = Path(match.group(1).strip())
        assert failed_stage.is_dir()
        failed_ledger = json.loads((failed_stage / "command-ledger.json").read_text(encoding="utf-8"))
        assert failed_ledger["commands"][-1]["label"] == "pre-tag-readiness"
        assert failed_ledger["commands"][-1]["exit_code"] == 17
        assert failed_ledger["commands"][-1]["receipts"] == []


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
