#!/usr/bin/env python3
"""Build and verify one content-addressed owner-manual Beta evidence bundle."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import re
import sys
import zipfile
import zlib

try:
    from desktop_qualification_evidence import REQUIRED_SMOKE_CHECKS, validate_signed_smoke_contract
except ModuleNotFoundError:
    _evidence_path = Path(__file__).with_name("desktop_qualification_evidence.py")
    _evidence_spec = importlib.util.spec_from_file_location("desktop_qualification_evidence", _evidence_path)
    assert _evidence_spec and _evidence_spec.loader
    _evidence_module = importlib.util.module_from_spec(_evidence_spec)
    _evidence_spec.loader.exec_module(_evidence_module)
    REQUIRED_SMOKE_CHECKS = _evidence_module.REQUIRED_SMOKE_CHECKS
    validate_signed_smoke_contract = _evidence_module.validate_signed_smoke_contract

_readiness_path = Path(__file__).with_name("verify-pre-tag-readiness.py")
_readiness_spec = importlib.util.spec_from_file_location("verify_pre_tag_readiness", _readiness_path)
assert _readiness_spec and _readiness_spec.loader
_readiness_module = importlib.util.module_from_spec(_readiness_spec)
_readiness_spec.loader.exec_module(_readiness_module)
verify_readiness = _readiness_module.verify


QUALIFICATION_MODE = "owner-manual"
EXPECTED_TEAM_ID = "24D6NXS6H7"
ARTIFACT_NAMES = ("Intentive.zip", "intentive.dmg", "Intentive.Beta.zip", "intentive-beta.dmg")
RECEIPT_NAMES = (
    "release.json",
    "candidate-gate.json",
    "provider-smoke-stable.json",
    "provider-smoke-beta.json",
    "owner-smoke-stable.json",
    "owner-smoke-beta.json",
    "pre-tag-readiness.json",
    "source-t2-manifest.json",
    "fault-manifest.json",
    "backend-compatibility.json",
    "command-ledger.json",
)
MANIFEST_NAME = "owner-manual-evidence.json"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
DIGEST_RE = re.compile(r"^[0-9a-f]{64}$")
TAG_RE = re.compile(r"^v(?P<version>\d+\.\d+(?:\.\d+)?)\+(?P<build>[1-9]\d*)-macos$")
ASSET_RE = re.compile(r"^owner-manual-qualification-([0-9a-f]{40})-([0-9a-f]{64})[.]zip$")
MAX_BUNDLE_BYTES = 16 * 1024 * 1024
MAX_RECEIPT_BYTES = 1024 * 1024
REQUIRED_LEDGER_LABELS = frozenset(
    {
        "pre-tag-readiness",
        "candidate-gate",
        "stable-signed-smoke",
        "beta-signed-smoke",
        "source-t2",
        "fault-suite",
    }
)
UTC_RFC3339_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:[.][0-9]{1,6})?Z$")
RECEIPT_TIMESTAMP_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:[.][0-9]{1,6})?(?:Z|[+]00:00)$"
)
LEDGER_RECEIPTS = {
    "pre-tag-readiness": "pre-tag-readiness.json",
    "candidate-gate": "candidate-gate.json",
    "stable-signed-smoke": "owner-smoke-stable.json",
    "beta-signed-smoke": "owner-smoke-beta.json",
    "source-t2": "source-t2-manifest.json",
    "fault-suite": "fault-manifest.json",
}
LEDGER_ARGV = {
    "pre-tag-readiness": ("pre-tag-readiness.sh",),
    "candidate-gate": ("check-desktop-auto-beta-candidate.py", "--qualification-mode", "owner-manual"),
    "stable-signed-smoke": ("smoke-signed-desktop-artifact.sh", "com.heyintentive.intentive"),
    "beta-signed-smoke": ("smoke-signed-desktop-artifact.sh", "com.heyintentive.intentive.beta"),
    "source-t2": ("qualify-desktop-beta.sh", "--automatic"),
    "fault-suite": ("qualify-desktop-beta.sh", "--automatic"),
}


def _fail(message: str) -> None:
    raise ValueError(f"owner-manual qualification {message}")


def _json_object(raw: bytes, label: str) -> dict[str, object]:
    try:
        value: object = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"owner-manual qualification {label} is not valid JSON") from exc
    if not isinstance(value, dict) or any(not isinstance(key, str) for key in value):
        _fail(f"{label} must be a JSON object")
    return value


def _timestamp(value: object, label: str) -> datetime:
    if not isinstance(value, str) or RECEIPT_TIMESTAMP_RE.fullmatch(value) is None:
        _fail(f"{label} timestamp is invalid")
    try:
        parsed = datetime.fromisoformat(value.removesuffix("Z") + ("+00:00" if value.endswith("Z") else ""))
    except ValueError as exc:
        raise ValueError(f"owner-manual qualification {label} timestamp is invalid") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timedelta(0):
        _fail(f"{label} timestamp is invalid")
    return parsed.astimezone(timezone.utc)


def _duration(value: object, label: str) -> timedelta:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        _fail(f"{label} duration is invalid")
    return timedelta(seconds=float(value))


def _artifact_digests(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or set(value) != set(ARTIFACT_NAMES):
        _fail("must bind the exact stable/Beta artifact digests")
    result: dict[str, str] = {}
    for name in ARTIFACT_NAMES:
        digest = value.get(name)
        if not isinstance(digest, str) or DIGEST_RE.fullmatch(digest) is None:
            _fail("must bind the exact stable/Beta artifact digests")
        result[name] = digest
    return result


def _smoke_artifact(receipt: dict[str, object], label: str) -> str:
    artifacts = receipt.get("artifacts")
    if not isinstance(artifacts, list):
        _fail("signed-smoke receipt is invalid")
    matches = [item for item in artifacts if isinstance(item, dict) and item.get("label") == label]
    if len(matches) != 1 or not isinstance(matches[0].get("sha256"), str):
        _fail("signed-smoke receipt is invalid")
    return str(matches[0]["sha256"])


def _validate_smoke(
    receipt: dict[str, object],
    *,
    tag: str,
    source_sha: str,
    bundle_id: str,
    zip_name: str,
    dmg_name: str,
    digests: dict[str, str],
) -> None:
    match = TAG_RE.fullmatch(tag)
    if match is None:
        _fail("release identity is invalid")
    try:
        validate_signed_smoke_contract(
            receipt,
            bundle_id=bundle_id,
            release_tag=tag,
            expected_version=match.group("version"),
            expected_build=match.group("build"),
            expected_source_sha=source_sha,
            expected_team_id=EXPECTED_TEAM_ID,
            label="owner-manual",
        )
    except ValueError as exc:
        raise ValueError("owner-manual qualification signed-smoke receipt is invalid") from exc
    if _smoke_artifact(receipt, "sparkle_zip") != digests[zip_name]:
        _fail("signed-smoke ZIP digest does not bind the candidate")
    if _smoke_artifact(receipt, "dmg") != digests[dmg_name]:
        _fail("signed-smoke DMG digest does not bind the candidate")


def _validate_receipts(receipts: dict[str, bytes], tag: str, source_sha: str) -> dict[str, str]:
    if set(receipts) != set(RECEIPT_NAMES):
        _fail("requires the exact receipt set")
    values = {name: _json_object(raw, name) for name, raw in receipts.items()}
    release = values["release.json"]
    if (
        release.get("tagName") != tag
        or release.get("isDraft") is not False
        or release.get("isPrerelease") is not False
        or not isinstance(release.get("publishedAt"), str)
        or UTC_RFC3339_RE.fullmatch(str(release.get("publishedAt"))) is None
    ):
        _fail("release receipt is invalid")
    release_published = _timestamp(release.get("publishedAt"), "release")
    gate = values["candidate-gate.json"]
    if (
        gate.get("passed") is not True
        or gate.get("qualification_mode") != QUALIFICATION_MODE
        or gate.get("release_tag") != tag
        or gate.get("source_sha") != source_sha
    ):
        _fail("candidate gate does not bind owner-manual qualification")
    candidate_finished = _timestamp(gate.get("verified_at"), "candidate gate")
    digests = _artifact_digests(gate.get("artifact_digests"))
    for prefix in ("provider", "owner"):
        _validate_smoke(
            values[f"{prefix}-smoke-stable.json"],
            tag=tag,
            source_sha=source_sha,
            bundle_id="com.heyintentive.intentive",
            zip_name="Intentive.zip",
            dmg_name="intentive.dmg",
            digests=digests,
        )
        _validate_smoke(
            values[f"{prefix}-smoke-beta.json"],
            tag=tag,
            source_sha=source_sha,
            bundle_id="com.heyintentive.intentive.beta",
            zip_name="Intentive.Beta.zip",
            dmg_name="intentive-beta.dmg",
            digests=digests,
        )
    owner_stable_finished = _timestamp(values["owner-smoke-stable.json"].get("finished_at"), "stable smoke")
    owner_beta_finished = _timestamp(values["owner-smoke-beta.json"].get("finished_at"), "beta smoke")
    team_ids = {
        values[name].get("team_id")
        for name in (
            "provider-smoke-stable.json",
            "provider-smoke-beta.json",
            "owner-smoke-stable.json",
            "owner-smoke-beta.json",
        )
    }
    if len(team_ids) != 1:
        _fail("signed-smoke receipts disagree on Apple Team identity")
    readiness = values["pre-tag-readiness.json"]
    try:
        verify_readiness(readiness, source_sha)
    except ValueError as exc:
        raise ValueError("owner-manual qualification pre-tag readiness receipt is invalid") from exc
    if readiness.get("lane") != "local":
        _fail("pre-tag readiness receipt is invalid")
    readiness_finished = _timestamp(readiness.get("started_at"), "pre-tag readiness") + _duration(
        readiness.get("duration_s"), "pre-tag readiness"
    )
    tag_match = TAG_RE.fullmatch(tag)
    assert tag_match is not None
    source_t2 = values["source-t2-manifest.json"]
    if (
        source_t2.get("passed") is not True
        or source_t2.get("tier") not in {2, "2"}
        or source_t2.get("provider_mode") != "offline"
        or source_t2.get("git_sha") != source_sha
        or source_t2.get("repository_git_sha") != source_sha
        or source_t2.get("bundle") != f"omi-qualification-{tag_match.group('version')}+{tag_match.group('build')}"
        or source_t2.get("source_provenance") != "bundle-health"
        or source_t2.get("source_tree_dirty") is not False
    ):
        _fail("source T2 receipt is invalid")
    source_t2_finished = _timestamp(source_t2.get("started_at"), "source T2") + _duration(
        source_t2.get("duration_s"), "source T2"
    )
    fault = values["fault-manifest.json"]
    if (
        fault.get("passed") is not True
        or fault.get("tier") != "fault"
        or fault.get("provider_mode") != "offline"
        or fault.get("git_sha") != source_sha
        or fault.get("repository_git_sha") != source_sha
        or not isinstance(fault.get("bundle"), str)
        or not str(fault.get("bundle")).startswith("omi-fault-")
        or fault.get("source_provenance") != "bundle-health"
        or fault.get("source_tree_dirty") is not False
    ):
        _fail("fault-suite receipt is invalid")
    fault_finished = _timestamp(fault.get("started_at"), "fault suite") + _duration(
        fault.get("duration_s"), "fault suite"
    )
    compatibility = values["backend-compatibility.json"]
    if compatibility != {
        "schema_version": 1,
        "status": "healthy",
        "service": "backend",
        "process_health_status": "ok",
        "chat_contract_version": "1",
    }:
        _fail("backend compatibility receipt is invalid")
    ledger = values["command-ledger.json"]
    commands = ledger.get("commands")
    if (
        ledger.get("schema_version") != 1
        or ledger.get("qualification_mode") != QUALIFICATION_MODE
        or ledger.get("release_tag") != tag
        or ledger.get("source_sha") != source_sha
        or not isinstance(commands, list)
    ):
        _fail("command ledger is invalid")
    labels: set[str] = set()
    receipt_finished = {
        "pre-tag-readiness": readiness_finished,
        "candidate-gate": candidate_finished,
        "stable-signed-smoke": owner_stable_finished,
        "beta-signed-smoke": owner_beta_finished,
        "source-t2": source_t2_finished,
        "fault-suite": fault_finished,
    }
    for command in commands:
        if (
            not isinstance(command, dict)
            or not isinstance(command.get("label"), str)
            or not isinstance(command.get("argv"), list)
            or not command["argv"]
            or any(not isinstance(part, str) or not part for part in command["argv"])
            or command.get("exit_code") != 0
            or not isinstance(command.get("recorded_at"), str)
        ):
            _fail("command ledger is invalid")
        label = str(command["label"])
        labels.add(label)
        expected_argv = LEDGER_ARGV.get(label)
        if expected_argv is None or tuple(command["argv"][: len(expected_argv)]) != expected_argv:
            _fail("command ledger is invalid")
        recorded_at = _timestamp(command.get("recorded_at"), f"{label} command")
        if recorded_at < release_published or recorded_at < receipt_finished[label]:
            _fail("command ledger timestamp predates its command receipt")
        receipt_name = LEDGER_RECEIPTS.get(label)
        if receipt_name is not None and (
            command.get("receipt") != receipt_name
            or command.get("receipt_sha256") != hashlib.sha256(receipts[receipt_name]).hexdigest()
        ):
            _fail("command ledger does not bind its receipt bytes")
    if labels != REQUIRED_LEDGER_LABELS or len(commands) != len(REQUIRED_LEDGER_LABELS):
        _fail("command ledger is invalid")
    return digests


def _zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100600 << 16
    return info


def build_bundle(receipt_paths: dict[str, Path], output_dir: Path, release_tag: str, source_sha: str) -> Path:
    if TAG_RE.fullmatch(release_tag) is None or SHA_RE.fullmatch(source_sha) is None:
        _fail("release identity is invalid")
    if set(receipt_paths) != set(RECEIPT_NAMES):
        _fail("requires the exact receipt set")
    receipts: dict[str, bytes] = {}
    for name, path in receipt_paths.items():
        raw = path.read_bytes()
        if not raw or len(raw) > MAX_RECEIPT_BYTES:
            _fail(f"{name} size is invalid")
        receipts[name] = raw
    artifact_digests = _validate_receipts(receipts, release_tag, source_sha)
    manifest = {
        "schema_version": 1,
        "qualification_mode": QUALIFICATION_MODE,
        "release_id": release_tag,
        "source_sha": source_sha,
        "artifact_digests": artifact_digests,
        "receipt_sha256": {name: hashlib.sha256(receipts[name]).hexdigest() for name in RECEIPT_NAMES},
    }
    manifest_bytes = json.dumps(manifest, indent=2, sort_keys=True).encode() + b"\n"
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr(_zip_info(MANIFEST_NAME), manifest_bytes)
        for name in RECEIPT_NAMES:
            archive.writestr(_zip_info(name), receipts[name])
    payload = output.getvalue()
    if len(payload) > MAX_BUNDLE_BYTES:
        _fail("evidence bundle is too large")
    digest = hashlib.sha256(payload).hexdigest()
    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / f"owner-manual-qualification-{source_sha}-{digest}.zip"
    target.write_bytes(payload)
    target.chmod(0o600)
    return target


def verify_bundle(
    payload: bytes, release_tag: str, source_sha: str, artifact_digests: dict[str, str]
) -> dict[str, object]:
    if not payload or len(payload) > MAX_BUNDLE_BYTES:
        _fail("evidence bundle size is invalid")
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            infos = archive.infolist()
            if len(infos) != len(RECEIPT_NAMES) + 1 or {info.filename for info in infos} != {
                MANIFEST_NAME,
                *RECEIPT_NAMES,
            }:
                _fail("evidence bundle has unexpected contents")
            if any(
                info.is_dir()
                or info.flag_bits & 0x1
                or info.file_size < 1
                or info.file_size > MAX_RECEIPT_BYTES
                or info.compress_size < 0
                or info.compress_size > MAX_BUNDLE_BYTES
                for info in infos
            ):
                _fail("evidence bundle has unsafe contents")
            members = {info.filename: archive.read(info) for info in infos}
    except (EOFError, OSError, RuntimeError, zipfile.BadZipFile, zipfile.LargeZipFile, zlib.error) as exc:
        raise ValueError("owner-manual qualification evidence bundle is not a safe ZIP") from exc
    receipts = {name: members[name] for name in RECEIPT_NAMES}
    verified_digests = _validate_receipts(receipts, release_tag, source_sha)
    expected_digests = _artifact_digests(artifact_digests)
    if verified_digests != expected_digests:
        _fail("artifact digests differ from release bytes")
    manifest = _json_object(members[MANIFEST_NAME], MANIFEST_NAME)
    expected_manifest = {
        "schema_version": 1,
        "qualification_mode": QUALIFICATION_MODE,
        "release_id": release_tag,
        "source_sha": source_sha,
        "artifact_digests": expected_digests,
        "receipt_sha256": {name: hashlib.sha256(receipts[name]).hexdigest() for name in RECEIPT_NAMES},
    }
    if manifest != expected_manifest:
        _fail("manifest does not bind exact receipt bytes")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    build.add_argument("--release-tag", required=True)
    build.add_argument("--source-sha", required=True)
    build.add_argument("--output-directory", type=Path, required=True)
    build.add_argument("--receipt", action="append", default=[])
    verify = sub.add_parser("verify")
    verify.add_argument("--release-tag", required=True)
    verify.add_argument("--source-sha", required=True)
    verify.add_argument("--bundle", type=Path, required=True)
    verify.add_argument("--artifact-digest", action="append", default=[])
    args = parser.parse_args(argv)
    if args.command == "build":
        receipt_paths: dict[str, Path] = {}
        for raw in args.receipt:
            name, separator, path = raw.partition("=")
            if not separator or name in receipt_paths:
                parser.error("--receipt must be unique NAME=PATH")
            receipt_paths[name] = Path(path)
        print(build_bundle(receipt_paths, args.output_directory, args.release_tag, args.source_sha))
    else:
        digests: dict[str, str] = {}
        for raw in args.artifact_digest:
            name, separator, digest = raw.partition("=")
            if not separator or name in digests:
                parser.error("--artifact-digest must be unique NAME=SHA256")
            digests[name] = digest.removeprefix("sha256:")
        verify_bundle(args.bundle.read_bytes(), args.release_tag, args.source_sha, digests)
        print("owner-manual qualification evidence verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
