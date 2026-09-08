"""CLI implementation for top-level local dev harness make commands."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, replace
from enum import Enum
from pathlib import Path
from typing import Iterable, Mapping

from . import config, desktop_paths, desktop_profile, providers, qualification, safety, synthetic_profiles

OWNERSHIP_PREFIX = "omi-dev-harness"
CONFIG_DIGEST_SCHEMA_VERSION = 4
RUNTIME_SOURCE_PATHS = (
    "backend",
    "scripts/dev-harness",
    "firebase.json",
    "firestore.rules",
    "firestore.indexes.json",
)
DESKTOP_RECORD_SCHEMA_VERSION = 1
_DESKTOP_LAUNCH_TOKEN_RE = re.compile(r"[A-Za-z0-9_-]{16,128}")
_DESKTOP_SOURCE_SHA_RE = re.compile(r"[0-9a-f]{40}")
DESKTOP_RECORD_STATE_ATTEMPT = "launch_attempt"
DESKTOP_RECORD_STATE_OWNED = "owned"
DESKTOP_PROOF_LAUNCH_TOKEN = "launch_token"
DESKTOP_PROOF_BRIDGE_SUCCESSOR = "bridge_successor"
SERVICE_STOP_PHASES: tuple[tuple[signal.Signals, float], ...] = tuple(
    (signal.Signals(value), wait_seconds)
    for name, wait_seconds in (("SIGINT", 8.0), ("SIGTERM", 5.0), ("SIGKILL", 2.0))
    if (value := getattr(signal, name, None)) is not None
)


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


@dataclass(frozen=True, slots=True)
class DesktopLaunchAttempt:
    """Owner-only durable evidence written before the detached launcher runs."""

    instance: str
    automation_port: int
    app_name: str
    bundle_id: str
    app_path: Path
    executable_path: Path
    profile_root: Path
    state_root: Path
    launch_token: str
    attempted_at: str

    def as_record(self) -> dict[str, object]:
        return {
            "desktop_schema_version": DESKTOP_RECORD_SCHEMA_VERSION,
            "desktop_record_state": DESKTOP_RECORD_STATE_ATTEMPT,
            "service": "desktop",
            "instance": self.instance,
            "automation_port": self.automation_port,
            "app_name": self.app_name,
            "bundle_id": self.bundle_id,
            "app_path": str(self.app_path),
            "executable_path": str(self.executable_path),
            "profile_root": str(self.profile_root),
            "state_root": str(self.state_root),
            "launch_token": self.launch_token,
            "attempted_at": self.attempted_at,
        }


class DesktopOwnershipProof(str, Enum):
    LAUNCH_TOKEN = DESKTOP_PROOF_LAUNCH_TOKEN
    BRIDGE_SUCCESSOR = DESKTOP_PROOF_BRIDGE_SUCCESSOR


class DesktopSuccessorPending(safety.SafetyError):
    """An exact-path successor exists but has not completed health admission."""


@dataclass(frozen=True, slots=True)
class DesktopOwnershipRecord:
    """A parsed desktop record whose workspace and process proof are verified."""

    instance: str
    pid: int
    port: int
    app_name: str
    bundle_id: str
    app_path: Path
    executable_path: Path
    profile_root: Path
    state_root: Path
    launch_token: str
    launch_transport: str
    process_start: str
    command_sha256: str
    proof: DesktopOwnershipProof
    started_at: str
    source_git_sha: str | None = None
    source_tree_dirty: bool | None = None
    predecessor_pid: int | None = None
    predecessor_process_start: str | None = None
    predecessor_command_sha256: str | None = None

    def as_record(self) -> dict[str, object]:
        record: dict[str, object] = {
            "desktop_schema_version": DESKTOP_RECORD_SCHEMA_VERSION,
            "desktop_record_state": DESKTOP_RECORD_STATE_OWNED,
            "desktop_ownership_proof": self.proof.value,
            "service": "desktop",
            "instance": self.instance,
            "pid": self.pid,
            "port": self.port,
            "owned_ports": {"automation": self.port},
            "endpoint": f"127.0.0.1:{self.port}",
            "app_name": self.app_name,
            "bundle_id": self.bundle_id,
            "app_path": str(self.app_path),
            "executable_path": str(self.executable_path),
            "profile_root": str(self.profile_root),
            "state_root": str(self.state_root),
            "launch_token": self.launch_token,
            "launch_transport": self.launch_transport,
            "process_start": self.process_start,
            "command_sha256": self.command_sha256,
            "started_at": self.started_at,
        }
        if self.source_git_sha is not None:
            record["source_git_sha"] = self.source_git_sha
            record["source_tree_dirty"] = self.source_tree_dirty
        if self.predecessor_pid is not None:
            record.update(
                {
                    "predecessor_pid": self.predecessor_pid,
                    "predecessor_process_start": self.predecessor_process_start,
                    "predecessor_command_sha256": self.predecessor_command_sha256,
                }
            )
        return record


def _repo_root() -> Path:
    return config.repo_root_from(Path.cwd())


def _marker(cfg: config.HarnessConfig, service: str) -> str:
    token = os.environ.get("OMI_HARNESS_OWNERSHIP_TOKEN", "").strip()
    return (
        f"{OWNERSHIP_PREFIX}:{cfg.instance}:{service}:{token}"
        if token
        else f"{OWNERSHIP_PREFIX}:{cfg.instance}:{service}"
    )


def _load_json(path: Path, default: dict[str, object]) -> dict[str, object]:
    if not path.is_file():
        return default
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default
    return data if isinstance(data, dict) else default


def _write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.{secrets.token_hex(8)}.tmp")
    try:
        temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _json_digest(data: object) -> str:
    payload = json.dumps(data, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _runtime_source_contract(repo_root: Path) -> dict[str, object]:
    """Fingerprint every source/dependency input used by the owned backend."""

    def run_git(args: list[str], *, binary: bool = False) -> str | bytes:
        result = subprocess.run(
            ["git", *args],
            cwd=repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=not binary,
            timeout=10,
        )
        if result.returncode != 0:
            detail = result.stderr.decode(errors="replace") if binary else result.stderr
            raise RuntimeError(f"cannot fingerprint harness runtime source: git {' '.join(args)}: {detail.strip()}")
        return result.stdout

    sha = str(run_git(["rev-parse", "HEAD"])).strip()
    if len(sha) != 40 or any(character not in "0123456789abcdef" for character in sha):
        raise RuntimeError("cannot fingerprint harness runtime source: HEAD is not a full Git SHA")
    pathspec = ["--", *RUNTIME_SOURCE_PATHS]
    status = bytes(run_git(["status", "--porcelain=v1", "-z", "--untracked-files=all", *pathspec], binary=True))
    diff = bytes(run_git(["diff", "--binary", "HEAD", *pathspec], binary=True))
    untracked = bytes(run_git(["ls-files", "--others", "--exclude-standard", "-z", *pathspec], binary=True))

    digest = hashlib.sha256()
    digest.update(sha.encode("ascii"))
    digest.update(b"\0tracked-diff\0")
    digest.update(diff)
    digest.update(b"\0untracked-files\0")
    for raw_path in sorted(path for path in untracked.split(b"\0") if path):
        relative = raw_path.decode("utf-8", errors="surrogateescape")
        source_path = repo_root / relative
        if not source_path.is_file():
            raise RuntimeError(f"cannot fingerprint harness runtime source: untracked input is not a file: {relative}")
        digest.update(raw_path)
        digest.update(b"\0")
        digest.update(source_path.read_bytes())
        digest.update(b"\0")
    return {
        "repository_git_sha": sha,
        "tree_dirty": bool(status),
        "fingerprint_sha256": digest.hexdigest(),
        "pathspec": list(RUNTIME_SOURCE_PATHS),
    }


def _process_records(cfg: config.HarnessConfig) -> list[dict[str, object]]:
    records = _load_json(cfg.layout.process_manifest, {"processes": []}).get("processes", [])
    return records if isinstance(records, list) else []


def _owned_live_process_records(cfg: config.HarnessConfig) -> list[dict[str, object]]:
    owned: list[dict[str, object]] = []
    for record in _process_records(cfg):
        try:
            service = str(record.get("service", ""))
            pid = int(record.get("pid", -1))
            marker = str(record.get("ownership_marker", ""))
        except (AttributeError, TypeError, ValueError):
            continue
        if service == "desktop":
            try:
                if record.get("desktop_record_state") == DESKTOP_RECORD_STATE_ATTEMPT:
                    _desktop_launch_attempt(cfg, record)
                    owned.append(record)
                    continue
                recovered = recover_desktop_record(cfg, record)
                if _validated_desktop_process(cfg, recovered) is not None:
                    owned.append(recovered)
            except DesktopSuccessorPending:
                # An exact executable is already taking over the recorded
                # bundle; keep the active launch contract until admission.
                owned.append(record)
            except safety.SafetyError:
                pass
            continue
        expected_marker = f"{OWNERSHIP_PREFIX}:{cfg.instance}:{service}"
        if not service or (marker != expected_marker and not marker.startswith(f"{expected_marker}:")):
            continue
        try:
            safety.validate_owned_pid(pid, process_manifest=cfg.layout.process_manifest, service=service)
        except safety.SafetyError:
            continue
        owned.append(record)
    return owned


def _current_provider_report(cfg: config.HarnessConfig) -> providers.ProviderPreflight:
    provider_env = config.preflight_env(cfg)
    provider_env["PROVIDER_MODE"] = cfg.provider_mode
    return providers.provider_preflight(cfg.repo_root, env=provider_env)


def _provider_budgets() -> dict[str, object]:
    return {
        "session_usd": providers.DEFAULT_SESSION_BUDGET_USD,
        "day_usd": providers.DEFAULT_DAILY_BUDGET_USD,
        "concurrency": providers.DEFAULT_MAX_CONCURRENCY,
        "idempotent_retries": providers.DEFAULT_IDEMPOTENT_RETRIES,
        "non_idempotent_retries": providers.DEFAULT_NON_IDEMPOTENT_RETRIES,
        "automatic_replay_after_restart": False,
    }


def _launch_contract(
    cfg: config.HarnessConfig,
    provider_report: providers.ProviderPreflight,
) -> dict[str, object]:
    return {
        "project_id": cfg.project_id,
        "database_id": cfg.database_id,
        "provider_mode": cfg.provider_mode,
        "enabled_external_providers": list(provider_report.enabled_external_providers),
        "credential_fingerprints": dict(provider_report.fingerprints),
        "offline_fake_sources": dict(provider_report.offline_fake_sources),
        "provider_budgets": _provider_budgets(),
        "runtime_source": _runtime_source_contract(cfg.repo_root),
        "instance": cfg.instance,
        "state_root": str(cfg.layout.state_root),
        "ports": {
            "firestore": cfg.firestore_port,
            "auth": cfg.auth_port,
            "redis": cfg.redis_port,
            "backend": cfg.backend_port,
            "automation": cfg.automation_port,
            "firestore_websocket": cfg.firestore_websocket_port,
            "firebase_hub": cfg.firebase_hub_port,
            "firebase_logging": cfg.firebase_logging_port,
            "firebase_ui": cfg.firebase_ui_port,
        },
        "endpoints": {
            "firestore": cfg.firestore_host,
            "auth": cfg.auth_host,
            "redis": f"{cfg.redis_host}:{cfg.redis_port}",
            "backend": cfg.backend_url,
            "automation": f"127.0.0.1:{cfg.automation_port}",
            "firestore_websocket": f"127.0.0.1:{cfg.firestore_websocket_port}",
            "firebase_hub": f"127.0.0.1:{cfg.firebase_hub_port}",
            "firebase_logging": f"127.0.0.1:{cfg.firebase_logging_port}",
            "firebase_ui": f"127.0.0.1:{cfg.firebase_ui_port}",
        },
    }


def _config_digest(
    cfg: config.HarnessConfig,
    provider_report: providers.ProviderPreflight,
) -> dict[str, object]:
    return {
        "schema_version": CONFIG_DIGEST_SCHEMA_VERSION,
        "updated_at": _now(),
        **_launch_contract(cfg, provider_report),
    }


def _digest_launch_contract(digest: dict[str, object]) -> dict[str, object]:
    return {key: digest.get(key) for key in _launch_contract_keys()}


def _launch_contract_keys() -> tuple[str, ...]:
    return (
        "project_id",
        "database_id",
        "provider_mode",
        "enabled_external_providers",
        "credential_fingerprints",
        "offline_fake_sources",
        "provider_budgets",
        "runtime_source",
        "instance",
        "state_root",
        "ports",
        "endpoints",
    )


def _validated_active_digest(requested: config.HarnessConfig) -> dict[str, object] | None:
    if not _owned_live_process_records(requested):
        return None
    digest = _load_json(requested.layout.config_digest_path, {})
    try:
        if digest.get("schema_version") != CONFIG_DIGEST_SCHEMA_VERSION:
            raise ValueError("schema")
        if digest.get("instance") != requested.instance:
            raise ValueError("instance")
        if digest.get("state_root") != str(requested.layout.state_root):
            raise ValueError("state_root")
        provider_mode = digest["provider_mode"]
        if provider_mode not in config.PROVIDER_MODES:
            raise ValueError("provider_mode")
        project_id = digest["project_id"]
        database_id = digest["database_id"]
        if not isinstance(project_id, str) or not project_id:
            raise ValueError("project_id")
        if not isinstance(database_id, str) or not database_id:
            raise ValueError("database_id")
        ports = digest["ports"]
        expected_port_names = {
            "firestore",
            "auth",
            "redis",
            "backend",
            "automation",
            "firestore_websocket",
            "firebase_hub",
            "firebase_logging",
            "firebase_ui",
        }
        if not isinstance(ports, dict) or set(ports) != expected_port_names:
            raise ValueError("ports")
        if any(not isinstance(ports[name], int) or not 1 <= ports[name] <= 65535 for name in ports):
            raise ValueError("ports")
        if len(set(ports.values())) != len(ports):
            raise ValueError("ports")
        endpoints = digest["endpoints"]
        expected_endpoints = {
            "firestore": f"127.0.0.1:{ports['firestore']}",
            "auth": f"127.0.0.1:{ports['auth']}",
            "redis": f"127.0.0.1:{ports['redis']}",
            "backend": f"http://127.0.0.1:{ports['backend']}",
            "automation": f"127.0.0.1:{ports['automation']}",
            "firestore_websocket": f"127.0.0.1:{ports['firestore_websocket']}",
            "firebase_hub": f"127.0.0.1:{ports['firebase_hub']}",
            "firebase_logging": f"127.0.0.1:{ports['firebase_logging']}",
            "firebase_ui": f"127.0.0.1:{ports['firebase_ui']}",
        }
        if endpoints != expected_endpoints:
            raise ValueError("endpoints")
        enabled = digest["enabled_external_providers"]
        fingerprints = digest["credential_fingerprints"]
        fake_sources = digest["offline_fake_sources"]
        if not isinstance(enabled, list) or any(not isinstance(item, str) for item in enabled):
            raise ValueError("enabled_external_providers")
        if not isinstance(fingerprints, dict) or any(
            not isinstance(key, str) or not isinstance(value, str) for key, value in fingerprints.items()
        ):
            raise ValueError("credential_fingerprints")
        if not isinstance(fake_sources, dict) or any(
            not isinstance(key, str) or not isinstance(value, str) for key, value in fake_sources.items()
        ):
            raise ValueError("offline_fake_sources")
        if digest["provider_budgets"] != _provider_budgets():
            raise ValueError("provider_budgets")
        runtime_source = digest["runtime_source"]
        if not isinstance(runtime_source, dict) or set(runtime_source) != {
            "repository_git_sha",
            "tree_dirty",
            "fingerprint_sha256",
            "pathspec",
        }:
            raise ValueError("runtime_source")
        source_sha = runtime_source["repository_git_sha"]
        source_fingerprint = runtime_source["fingerprint_sha256"]
        if not isinstance(source_sha, str) or len(source_sha) != 40:
            raise ValueError("runtime_source")
        if not isinstance(source_fingerprint, str) or len(source_fingerprint) != 64:
            raise ValueError("runtime_source")
        if not isinstance(runtime_source["tree_dirty"], bool):
            raise ValueError("runtime_source")
        if runtime_source["pathspec"] != list(RUNTIME_SOURCE_PATHS):
            raise ValueError("runtime_source")
    except (KeyError, TypeError, ValueError):
        raise RuntimeError(
            "owned services are live but their complete launch evidence is missing or invalid; run make dev-down"
        ) from None
    if digest["runtime_source"] != _runtime_source_contract(requested.repo_root):
        raise RuntimeError(
            "owned services are live but their backend/harness source or dependency fingerprint is stale; "
            "run make dev-down"
        )
    return digest


def _provider_report_from_digest(digest: dict[str, object]) -> providers.ProviderPreflight:
    return providers.ProviderPreflight(
        mode=str(digest["provider_mode"]),
        enabled_external_providers=tuple(str(item) for item in digest["enabled_external_providers"]),
        fingerprints=dict(digest["credential_fingerprints"]),
        offline_fake_sources=dict(digest["offline_fake_sources"]),
    )


def active_runtime_config(
    requested: config.HarnessConfig,
) -> tuple[config.HarnessConfig, str | None]:
    digest = _validated_active_digest(requested)
    if digest is None:
        return requested, None
    ports = digest["ports"]
    assert isinstance(ports, dict)
    active_mode = str(digest["provider_mode"])
    active = replace(
        requested,
        provider_mode=active_mode,
        project_id=str(digest["project_id"]),
        database_id=str(digest["database_id"]),
        firestore_port=int(ports["firestore"]),
        auth_port=int(ports["auth"]),
        redis_host="127.0.0.1",
        redis_port=int(ports["redis"]),
        backend_port=int(ports["backend"]),
        automation_port=int(ports["automation"]),
        firestore_websocket_port=int(ports["firestore_websocket"]),
        firebase_hub_port=int(ports["firebase_hub"]),
        firebase_logging_port=int(ports["firebase_logging"]),
        firebase_ui_port=int(ports["firebase_ui"]),
    )
    requested_mode = requested.provider_mode if active_mode != requested.provider_mode else None
    return active, requested_mode


def _runtime_provider_report(cfg: config.HarnessConfig) -> providers.ProviderPreflight:
    digest = _validated_active_digest(cfg)
    return _provider_report_from_digest(digest) if digest is not None else _current_provider_report(cfg)


def prepare_provider_mode_for_start(requested: config.HarnessConfig) -> str | None:
    """Return the proven live mode or clear stale evidence before a fresh start."""
    if not _owned_live_process_records(requested):
        requested.layout.config_digest_path.unlink(missing_ok=True)
        return None
    raw_digest = _load_json(requested.layout.config_digest_path, {})
    active_mode = raw_digest.get("provider_mode")
    if not isinstance(active_mode, str) or active_mode not in config.PROVIDER_MODES:
        _validated_active_digest(requested)
        raise AssertionError("validated active digest did not provide a provider mode")
    if active_mode != requested.provider_mode:
        raise RuntimeError(
            f"owned services are already running in provider mode {active_mode}; "
            f"run make dev-down before starting mode {requested.provider_mode}"
        )
    digest = _validated_active_digest(requested)
    assert digest is not None
    expected = _launch_contract(requested, _current_provider_report(requested))
    if _digest_launch_contract(digest) != expected:
        raise RuntimeError(
            "owned services are already running but their complete launch contract differs from the requested "
            "configuration; run make dev-down before starting the new configuration"
        )
    return str(active_mode)


def _port_records(cfg: config.HarnessConfig) -> list[dict[str, object]]:
    records = _load_json(cfg.layout.port_manifest, {"ports": []}).get("ports", [])
    return records if isinstance(records, list) else []


def _save_manifests(cfg: config.HarnessConfig, records: list[dict[str, object]]) -> None:
    live: list[dict[str, object]] = []
    for record in records:
        if record.get("service") == "desktop":
            # A detached launch or an app-controlled/OS-controlled restart may
            # outlive the PID currently recorded here. Keep the exact attempt or
            # predecessor as the only authority from which a delayed process can
            # be recovered; explicit exact shutdown removes it.
            live.append(record)
            continue
        if safety.process_exists(int(record.get("pid", -1))):
            live.append(record)
            continue
        try:
            if any(safety.listening_pids(port) for port in _owned_record_ports(record)):
                live.append(record)
        except safety.SafetyError:
            # Listener discovery failure is not authority to erase the record
            # that explains why a service port may still be occupied.
            live.append(record)
    _write_json(cfg.layout.process_manifest, {"schema_version": 1, "updated_at": _now(), "processes": live})
    cfg.layout.process_manifest.chmod(0o600)
    ports: list[dict[str, object]] = []
    for record in live:
        owned_ports = record.get("owned_ports")
        if isinstance(owned_ports, dict):
            ports.extend(
                {
                    "name": name,
                    "service": record["service"],
                    "port": port,
                    "pid": record["pid"],
                    "endpoint": f"127.0.0.1:{port}",
                }
                for name, port in owned_ports.items()
            )
        elif "port" in record:
            ports.append(
                {
                    "service": record["service"],
                    "port": record["port"],
                    "pid": record["pid"],
                    "endpoint": record.get("endpoint"),
                }
            )
    _write_json(cfg.layout.port_manifest, {"schema_version": 1, "updated_at": _now(), "ports": ports})


def _port_open(host: str, port: int, timeout: float = 0.25) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _service_record(cfg: config.HarnessConfig, service: str) -> dict[str, object] | None:
    for record in _process_records(cfg):
        if record.get("service") != service:
            continue
        if service == "desktop":
            try:
                if _validated_desktop_process(cfg, record) is not None:
                    return record
            except safety.SafetyError:
                continue
        elif safety.process_exists(int(record.get("pid", -1))):
            return record
    return None


def desktop_app_path(profile: desktop_profile.DesktopLocalProfile) -> Path:
    return desktop_paths.configured_app_path(profile.app_name, profile.env)


def _record_app_path(app_name: str, app_path: Path) -> Path:
    # Resolve from the recorded root, not today's launch preference: an already
    # owned /Applications process must remain stoppable after opting into ~/Applications.
    try:
        return desktop_paths.dev_app_path(app_name, root=app_path.parent)
    except ValueError as exc:
        raise safety.SafetyError("Desktop record has an unsafe app path") from exc


def desktop_executable_path(profile: desktop_profile.DesktopLocalProfile) -> Path:
    return desktop_app_path(profile) / "Contents" / "MacOS" / "Omi Computer"


def desktop_profile_root(profile: desktop_profile.DesktopLocalProfile) -> Path:
    return Path(profile.application_support_dir).expanduser().resolve(strict=False)


def _expected_desktop_profile_root(bundle_id: str) -> Path:
    return (Path.home() / "Library" / "Application Support" / "Intentive Dev Bundles" / bundle_id).resolve(strict=False)


def _required_record_string(record: Mapping[str, object], key: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value:
        raise safety.SafetyError("Desktop record lacks complete typed provenance")
    return value


def _desktop_launch_attempt(cfg: config.HarnessConfig, record: Mapping[str, object]) -> DesktopLaunchAttempt:
    try:
        port = record["automation_port"]
        if not isinstance(port, int) or isinstance(port, bool):
            raise TypeError
        app_name = _required_record_string(record, "app_name")
        bundle_id = _required_record_string(record, "bundle_id")
        app_path = Path(_required_record_string(record, "app_path"))
        executable_path = Path(_required_record_string(record, "executable_path"))
        profile_root = Path(_required_record_string(record, "profile_root")).resolve(strict=False)
        token = _required_record_string(record, "launch_token")
        attempted_at = _required_record_string(record, "attempted_at")
    except (KeyError, TypeError, ValueError, safety.SafetyError):
        raise safety.SafetyError("Desktop record lacks complete typed provenance") from None
    expected_bundle = desktop_profile._local_bundle_id(app_name)
    expected_app = _record_app_path(app_name, app_path)
    expected_executable = expected_app / "Contents" / "MacOS" / "Omi Computer"
    if (
        record.get("desktop_schema_version") != DESKTOP_RECORD_SCHEMA_VERSION
        or record.get("desktop_record_state") != DESKTOP_RECORD_STATE_ATTEMPT
        or record.get("service") != "desktop"
        or record.get("instance") != cfg.instance
        or record.get("state_root") != str(cfg.layout.state_root)
        or not app_name.lower().startswith(desktop_profile.LOCAL_NAMED_BUNDLE_PREFIX)
        or bundle_id != expected_bundle
        or app_path != expected_app
        or executable_path != expected_executable
        or profile_root != _expected_desktop_profile_root(bundle_id)
        or port != cfg.automation_port
        or not _DESKTOP_LAUNCH_TOKEN_RE.fullmatch(token)
    ):
        raise safety.SafetyError("Desktop record lacks complete typed provenance for this workspace")
    return DesktopLaunchAttempt(
        instance=cfg.instance,
        automation_port=port,
        app_name=app_name,
        bundle_id=bundle_id,
        app_path=app_path,
        executable_path=executable_path,
        profile_root=profile_root,
        state_root=cfg.layout.state_root,
        launch_token=token,
        attempted_at=attempted_at,
    )


def _desktop_record_identity(cfg: config.HarnessConfig, record: Mapping[str, object]) -> DesktopOwnershipRecord:
    if record.get("desktop_record_state") == DESKTOP_RECORD_STATE_ATTEMPT:
        _desktop_launch_attempt(cfg, record)
        raise safety.SafetyError("Desktop launch attempt has not registered a process yet")
    try:
        pid = record["pid"]
        port = record["port"]
        if not isinstance(pid, int) or isinstance(pid, bool) or not isinstance(port, int) or isinstance(port, bool):
            raise TypeError
        app_name = _required_record_string(record, "app_name")
        bundle_id = _required_record_string(record, "bundle_id")
        app_path = Path(_required_record_string(record, "app_path"))
        executable_path = Path(_required_record_string(record, "executable_path"))
        profile_root = Path(_required_record_string(record, "profile_root")).resolve(strict=False)
        token = _required_record_string(record, "launch_token")
        process_start = _required_record_string(record, "process_start")
        command_sha256 = _required_record_string(record, "command_sha256")
        launch_transport = _required_record_string(record, "launch_transport")
        started_at = str(record.get("started_at") or "unknown")
    except (KeyError, TypeError, ValueError, safety.SafetyError):
        raise safety.SafetyError("Desktop record lacks complete typed provenance") from None
    try:
        proof = DesktopOwnershipProof(record.get("desktop_ownership_proof", DESKTOP_PROOF_LAUNCH_TOKEN))
    except (TypeError, ValueError):
        raise safety.SafetyError("Desktop record has an unknown ownership proof") from None
    source_git_sha = record.get("source_git_sha")
    source_tree_dirty = record.get("source_tree_dirty")
    if source_git_sha is not None:
        if (
            not isinstance(source_git_sha, str)
            or not _DESKTOP_SOURCE_SHA_RE.fullmatch(source_git_sha)
            or not isinstance(source_tree_dirty, bool)
        ):
            raise safety.SafetyError("Desktop record lacks complete typed source provenance")
    elif source_tree_dirty is not None:
        raise safety.SafetyError("Desktop record lacks complete typed source provenance")
    predecessor_pid = record.get("predecessor_pid")
    predecessor_process_start = record.get("predecessor_process_start")
    predecessor_command_sha256 = record.get("predecessor_command_sha256")
    if proof is DesktopOwnershipProof.BRIDGE_SUCCESSOR:
        if (
            not isinstance(predecessor_pid, int)
            or isinstance(predecessor_pid, bool)
            or predecessor_pid <= 0
            or not isinstance(predecessor_process_start, str)
            or not isinstance(predecessor_command_sha256, str)
            or not safety.valid_process_fingerprint(predecessor_process_start, predecessor_command_sha256)
            or source_git_sha is None
        ):
            raise safety.SafetyError("Desktop successor record lacks complete typed predecessor provenance")
    expected_bundle = desktop_profile._local_bundle_id(app_name)
    expected_app = _record_app_path(app_name, app_path)
    expected_executable = expected_app / "Contents" / "MacOS" / "Omi Computer"
    if (
        record.get("desktop_schema_version") != DESKTOP_RECORD_SCHEMA_VERSION
        or record.get("desktop_record_state", DESKTOP_RECORD_STATE_OWNED) != DESKTOP_RECORD_STATE_OWNED
        or record.get("service") != "desktop"
        or record.get("instance") != cfg.instance
        or record.get("state_root") != str(cfg.layout.state_root)
        or pid <= 0
        or not app_name.lower().startswith(desktop_profile.LOCAL_NAMED_BUNDLE_PREFIX)
        or bundle_id != expected_bundle
        or app_path != expected_app
        or executable_path != expected_executable
        or profile_root != _expected_desktop_profile_root(bundle_id)
        or port != cfg.automation_port
        or record.get("owned_ports") != {"automation": cfg.automation_port}
        or not _DESKTOP_LAUNCH_TOKEN_RE.fullmatch(token)
        or launch_transport not in {"open", "direct", "attempt_recovery", "successor"}
        or not safety.valid_process_fingerprint(process_start, command_sha256)
    ):
        raise safety.SafetyError("Desktop record lacks complete typed provenance for this workspace")
    return DesktopOwnershipRecord(
        instance=cfg.instance,
        pid=pid,
        port=port,
        app_name=app_name,
        bundle_id=bundle_id,
        app_path=app_path,
        executable_path=executable_path,
        profile_root=profile_root,
        state_root=cfg.layout.state_root,
        launch_token=token,
        launch_transport=launch_transport,
        process_start=process_start,
        command_sha256=command_sha256,
        proof=proof,
        started_at=started_at,
        source_git_sha=source_git_sha,
        source_tree_dirty=source_tree_dirty if isinstance(source_tree_dirty, bool) else None,
        predecessor_pid=predecessor_pid if isinstance(predecessor_pid, int) else None,
        predecessor_process_start=(predecessor_process_start if isinstance(predecessor_process_start, str) else None),
        predecessor_command_sha256=(
            predecessor_command_sha256 if isinstance(predecessor_command_sha256, str) else None
        ),
    )


def _process_executes_exact_path(process: safety.ProcessSnapshot, executable_path: Path) -> bool:
    """Resolve the live text executable; a command substring is never ownership proof."""

    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-a", "-p", str(process.pid), "-d", "txt", "-Fn"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise safety.SafetyError(f"Cannot inspect desktop executable for PID {process.pid}") from exc
    if result.returncode == 1:
        return False
    if result.returncode != 0:
        raise safety.SafetyError(f"Cannot inspect desktop executable for PID {process.pid}")
    expected = executable_path.resolve(strict=False)
    loaded_paths = {
        Path(line[1:]).resolve(strict=False) for line in result.stdout.splitlines() if line.startswith("n/")
    }
    return expected in loaded_paths


def _command_has_launch_token(command: str, launch_token: str) -> bool:
    token_argument = f"--omi-launch-token={launch_token}"
    return any(argument == token_argument for argument in command.split())


def _command_may_run_executable(command: str, executable_path: Path) -> bool:
    expected = str(executable_path)
    return command == expected or command.startswith(f"{expected} ")


def _validated_desktop_process(
    cfg: config.HarnessConfig,
    record: dict[str, object],
) -> safety.ProcessSnapshot | None:
    identity = _desktop_record_identity(cfg, record)
    process = safety.process_snapshot(identity.pid)
    if process is None:
        return None
    if (
        not safety.matches_process_fingerprint(
            process,
            process_start=identity.process_start,
            command_sha256=identity.command_sha256,
        )
        or not _process_executes_exact_path(process, identity.executable_path)
        or (
            identity.proof is DesktopOwnershipProof.LAUNCH_TOKEN
            and not _command_has_launch_token(process.command, identity.launch_token)
        )
    ):
        raise safety.SafetyError("Desktop PID no longer matches its recorded launch provenance")
    return process


def _desktop_process_after_authorized_signal(
    identity: DesktopOwnershipRecord,
) -> safety.ProcessSnapshot | None:
    """Track an authorized shutdown by PID/start while macOS may shed argv and executable mappings."""

    process = safety.process_snapshot(identity.pid)
    if process is None:
        return None
    if process.process_start != identity.process_start:
        raise safety.SafetyError("Desktop PID changed identity during exact shutdown")
    return process


def _desktop_record_after_process_exit(
    cfg: config.HarnessConfig,
    record: dict[str, object],
) -> dict[str, object] | None:
    """Return successor/residue that prevents settlement, or None when the lifecycle is fully stopped."""

    identity = _desktop_record_identity(cfg, record)
    recovered = recover_desktop_record(cfg, record)
    if recovered != record:
        return recovered
    return record if safety.listening_pids(identity.port) else None


def _read_owner_only_launch_signal(path: Path) -> dict[str, str]:
    try:
        info = path.lstat()
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise safety.SafetyError(f"Desktop launch signal is missing: {path}") from exc
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        raise safety.SafetyError("Desktop launch signal is not an owner-only regular file")
    fields: dict[str, str] = {}
    for line in lines:
        if "=" not in line:
            raise safety.SafetyError("Desktop launch signal is malformed")
        key, value = line.split("=", 1)
        if not key or key in fields:
            raise safety.SafetyError("Desktop launch signal is malformed")
        fields[key] = value
    return fields


def register_desktop_launch(
    cfg: config.HarnessConfig,
    profile: desktop_profile.DesktopLocalProfile,
    *,
    signal_path: Path,
    launch_token: str,
) -> dict[str, object]:
    if not _DESKTOP_LAUNCH_TOKEN_RE.fullmatch(launch_token):
        raise safety.SafetyError("Desktop launch token is invalid")
    resolved_signal = signal_path.resolve(strict=False)
    manifests_root = (cfg.layout.state_root / "manifests").resolve(strict=False)
    if resolved_signal.parent != manifests_root:
        raise safety.SafetyError("Desktop launch signal escaped this workspace state root")
    fields = _read_owner_only_launch_signal(resolved_signal)
    expected_signal = {
        "schema_version": "1",
        "bundle_id": profile.bundle_id,
        "app_path": str(desktop_app_path(profile)),
        "executable_path": str(desktop_executable_path(profile)),
        "launch_token": launch_token,
    }
    if any(fields.get(key) != value for key, value in expected_signal.items()):
        raise safety.SafetyError("Desktop launch signal does not bind this workspace launch")
    transport = fields.get("launch_transport")
    if transport not in {"open", "direct"}:
        raise safety.SafetyError("Desktop launch signal has unknown transport")
    expected_executable = str(desktop_executable_path(profile))
    matches = tuple(
        process
        for process in safety.process_snapshots()
        if _command_has_launch_token(process.command, launch_token)
        and _command_may_run_executable(process.command, Path(expected_executable))
        and _process_executes_exact_path(process, Path(expected_executable))
    )
    if len(matches) != 1:
        raise safety.SafetyError(f"Desktop launch ownership is ambiguous (matching processes={len(matches)})")
    process = matches[0]
    record = DesktopOwnershipRecord(
        instance=cfg.instance,
        pid=process.pid,
        port=cfg.automation_port,
        app_name=profile.app_name,
        bundle_id=profile.bundle_id,
        app_path=desktop_app_path(profile),
        executable_path=Path(expected_executable),
        profile_root=desktop_profile_root(profile),
        state_root=cfg.layout.state_root,
        launch_token=launch_token,
        launch_transport=transport,
        process_start=process.process_start,
        command_sha256=hashlib.sha256(process.command.encode()).hexdigest(),
        proof=DesktopOwnershipProof.LAUNCH_TOKEN,
        started_at=_now(),
    ).as_record()
    records = [entry for entry in _process_records(cfg) if entry.get("service") != "desktop"]
    records.append(record)
    _save_manifests(cfg, records)
    return record


def _desktop_bridge_payload(port: int) -> dict[str, object]:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/health",
        headers={"Host": f"127.0.0.1:{port}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=0.8) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, TimeoutError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise safety.SafetyError(f"Desktop automation bridge is unavailable: {exc.__class__.__name__}") from exc
    if not isinstance(payload, dict):
        raise safety.SafetyError("Desktop automation bridge returned an invalid health payload")
    return payload


def _desktop_health_provenance(payload: Mapping[str, object]) -> tuple[str | None, bool | None]:
    source_git_sha = payload.get("sourceGitSHA")
    source_tree_dirty = payload.get("sourceTreeDirty")
    if source_git_sha is None and source_tree_dirty is None:
        return None, None
    if (
        not isinstance(source_git_sha, str)
        or not _DESKTOP_SOURCE_SHA_RE.fullmatch(source_git_sha)
        or not isinstance(source_tree_dirty, bool)
    ):
        raise safety.SafetyError("Desktop bridge returned invalid source provenance")
    return source_git_sha, source_tree_dirty


def _verified_desktop_successor_health(
    cfg: config.HarnessConfig,
    identity: DesktopOwnershipRecord,
    process: safety.ProcessSnapshot,
) -> tuple[str | None, bool | None] | None:
    listeners = safety.listening_pids(identity.port)
    if not listeners:
        return None
    if any(not safety.is_descendant_of(listener, process.pid) for listener in listeners):
        raise safety.SafetyError("Desktop successor listener is outside the candidate process lineage")
    try:
        payload = _desktop_bridge_payload(identity.port)
    except safety.SafetyError:
        return None
    backend_root = cfg.backend_url.rstrip("/")
    expected_backend_urls = (backend_root, f"{backend_root}/")
    expected_health = {
        "ok": True,
        "bundleIdentifier": identity.bundle_id,
        "processID": process.pid,
        "bridgePort": identity.port,
    }
    if (
        any(payload.get(key) != value for key, value in expected_health.items())
        or payload.get("backendURL") not in expected_backend_urls
    ):
        raise safety.SafetyError("Desktop successor bridge identity does not match the recorded workspace")
    return _desktop_health_provenance(payload)


def _replace_desktop_record(cfg: config.HarnessConfig, record: dict[str, object]) -> None:
    records = [entry for entry in _process_records(cfg) if entry.get("service") != "desktop"]
    records.append(record)
    _save_manifests(cfg, records)


def bind_desktop_source_provenance(
    cfg: config.HarnessConfig,
    record: dict[str, object],
) -> dict[str, object]:
    """Bind the first healthy launch to the exact bundle source reported by its bridge."""

    identity = _desktop_record_identity(cfg, record)
    process = _validated_desktop_process(cfg, record)
    if process is None:
        raise safety.SafetyError("Desktop process exited before source provenance was bound")
    provenance = _verified_desktop_successor_health(cfg, identity, process)
    if provenance is None:
        raise safety.SafetyError("Desktop bridge became unavailable before source provenance was bound")
    source_git_sha, source_tree_dirty = provenance
    if source_git_sha is None:
        return record
    bound = replace(
        identity,
        source_git_sha=source_git_sha,
        source_tree_dirty=source_tree_dirty,
    ).as_record()
    _replace_desktop_record(cfg, bound)
    return bound


def _ownership_from_attempt_process(
    attempt: DesktopLaunchAttempt,
    process: safety.ProcessSnapshot,
) -> DesktopOwnershipRecord:
    return DesktopOwnershipRecord(
        instance=attempt.instance,
        pid=process.pid,
        port=attempt.automation_port,
        app_name=attempt.app_name,
        bundle_id=attempt.bundle_id,
        app_path=attempt.app_path,
        executable_path=attempt.executable_path,
        profile_root=attempt.profile_root,
        state_root=attempt.state_root,
        launch_token=attempt.launch_token,
        launch_transport="attempt_recovery",
        process_start=process.process_start,
        command_sha256=hashlib.sha256(process.command.encode()).hexdigest(),
        proof=DesktopOwnershipProof.LAUNCH_TOKEN,
        started_at=attempt.attempted_at,
    )


def recover_desktop_record(
    cfg: config.HarnessConfig,
    record: dict[str, object],
) -> dict[str, object]:
    """Resolve one exact attempted process or one verified successor; never adopt by app name."""

    if record.get("desktop_record_state") == DESKTOP_RECORD_STATE_ATTEMPT:
        attempt = _desktop_launch_attempt(cfg, record)
        matches = tuple(
            process
            for process in safety.process_snapshots()
            if _command_has_launch_token(process.command, attempt.launch_token)
            and _command_may_run_executable(process.command, attempt.executable_path)
            and _process_executes_exact_path(process, attempt.executable_path)
        )
        if len(matches) > 1:
            raise safety.SafetyError(f"Desktop launch ownership is ambiguous (matching processes={len(matches)})")
        if not matches:
            return record
        recovered = _ownership_from_attempt_process(attempt, matches[0]).as_record()
        _replace_desktop_record(cfg, recovered)
        return recovered

    identity = _desktop_record_identity(cfg, record)
    current = _validated_desktop_process(cfg, record)
    if current is not None:
        return record
    candidates = tuple(
        process
        for process in safety.process_snapshots()
        if process.pid != identity.pid
        and _command_may_run_executable(process.command, identity.executable_path)
        and _process_executes_exact_path(process, identity.executable_path)
    )
    if len(candidates) > 1:
        raise safety.SafetyError(f"Desktop successor ownership is ambiguous (matching processes={len(candidates)})")
    if not candidates:
        return record
    successor = candidates[0]
    has_same_token = _command_has_launch_token(successor.command, identity.launch_token)
    has_other_token = any(argument.startswith("--omi-launch-token=") for argument in successor.command.split())
    if has_other_token and not has_same_token:
        raise safety.SafetyError("Desktop successor carries a different launch capability")
    provenance = _verified_desktop_successor_health(cfg, identity, successor)
    if provenance is None:
        raise DesktopSuccessorPending("Exact desktop successor is present but its bridge identity is not ready")
    source_git_sha, source_tree_dirty = provenance
    if identity.source_git_sha is not None and (
        source_git_sha != identity.source_git_sha or source_tree_dirty != identity.source_tree_dirty
    ):
        raise safety.SafetyError("Desktop successor source provenance differs from its predecessor")
    if not has_same_token and identity.source_git_sha is None:
        raise safety.SafetyError("Tokenless desktop successor lacks predecessor source provenance")
    proof = DesktopOwnershipProof.LAUNCH_TOKEN if has_same_token else DesktopOwnershipProof.BRIDGE_SUCCESSOR
    recovered = replace(
        identity,
        pid=successor.pid,
        launch_transport="successor",
        process_start=successor.process_start,
        command_sha256=hashlib.sha256(successor.command.encode()).hexdigest(),
        proof=proof,
        source_git_sha=source_git_sha,
        source_tree_dirty=source_tree_dirty,
        predecessor_pid=(identity.pid if proof is DesktopOwnershipProof.BRIDGE_SUCCESSOR else None),
        predecessor_process_start=(identity.process_start if proof is DesktopOwnershipProof.BRIDGE_SUCCESSOR else None),
        predecessor_command_sha256=(
            identity.command_sha256 if proof is DesktopOwnershipProof.BRIDGE_SUCCESSOR else None
        ),
    ).as_record()
    _replace_desktop_record(cfg, recovered)
    return recovered


def desktop_record_status(cfg: config.HarnessConfig, record: dict[str, object]) -> tuple[str, str]:
    try:
        process = _validated_desktop_process(cfg, record)
        if process is None:
            return "stopped", "recorded process is not running"
        listeners = safety.listening_pids(int(record["port"]))
        if not listeners:
            return "unhealthy", "automation port is closed"
        if any(not safety.is_descendant_of(listener, process.pid) for listener in listeners):
            raise safety.SafetyError("Desktop automation listener is outside the recorded process lineage")
        payload = _desktop_bridge_payload(int(record["port"]))
        expected_health = {
            "ok": True,
            "bundleIdentifier": record["bundle_id"],
            "processID": process.pid,
            "bridgePort": int(record["port"]),
        }
        # Swift normalizes a root backend URL with a trailing slash. Accept
        # only these equivalent roots, never another path, query or endpoint.
        if any(payload.get(key) != value for key, value in expected_health.items()) or payload.get(
            "backendURL"
        ) not in (cfg.backend_url, cfg.backend_url + "/"):
            raise safety.SafetyError("Desktop bridge identity does not match the recorded workspace")
        return "healthy", "exact process and bridge"
    except (KeyError, TypeError, ValueError, safety.SafetyError) as exc:
        return "stale/unowned", str(exc)


def stop_desktop_record(
    cfg: config.HarnessConfig,
    record: dict[str, object],
    *,
    wait_seconds: float = 8.0,
    kill_wait_seconds: float = 2.0,
) -> bool:
    if record.get("desktop_record_state") == DESKTOP_RECORD_STATE_ATTEMPT:
        record = recover_desktop_record(cfg, record)
        if record.get("desktop_record_state") == DESKTOP_RECORD_STATE_ATTEMPT:
            return False
        process = _validated_desktop_process(cfg, record)
    else:
        process = _validated_desktop_process(cfg, record)
        if process is None:
            residue = _desktop_record_after_process_exit(cfg, record)
            if residue is None:
                return True
            if residue == record:
                return False
            record = residue
            process = _validated_desktop_process(cfg, record)
    if process is None:
        return False
    identity = _desktop_record_identity(cfg, record)
    try:
        os.kill(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return _desktop_record_after_process_exit(cfg, record) is None
    except PermissionError as exc:
        raise safety.SafetyError(f"Cannot signal desktop PID {process.pid}: {exc}") from exc
    deadline = time.time() + wait_seconds
    while time.time() < deadline:
        current = _desktop_process_after_authorized_signal(identity)
        if current is None:
            return _desktop_record_after_process_exit(cfg, record) is None
        time.sleep(0.1)
    # SIGKILL is a new destructive action. Re-establish full executable/token
    # ownership after the passive TERM wait before escalating.
    current = _validated_desktop_process(cfg, record)
    if current is None:
        return _desktop_record_after_process_exit(cfg, record) is None
    kill_signal = getattr(signal, "SIGKILL", signal.SIGTERM)
    try:
        os.kill(current.pid, kill_signal)
    except ProcessLookupError:
        return _desktop_record_after_process_exit(cfg, record) is None
    except PermissionError as exc:
        raise safety.SafetyError(f"Cannot signal desktop PID {current.pid}: {exc}") from exc
    deadline = time.time() + kill_wait_seconds
    while time.time() < deadline:
        if _desktop_process_after_authorized_signal(identity) is None:
            return _desktop_record_after_process_exit(cfg, record) is None
        time.sleep(0.1)
    if _desktop_process_after_authorized_signal(identity) is not None:
        raise safety.SafetyError(f"Desktop PID {current.pid} is still running after exact shutdown")
    return _desktop_record_after_process_exit(cfg, record) is None


def stop_desktop_for_relaunch(
    cfg: config.HarnessConfig,
    profile: desktop_profile.DesktopLocalProfile,
    *,
    wait_seconds: float = 8.0,
) -> None:
    records = _process_records(cfg)
    desktops = [record for record in records if record.get("service") == "desktop"]
    if len(desktops) > 1:
        raise safety.SafetyError("Multiple desktop records exist for this workspace; refusing relaunch")
    if not desktops:
        return
    record = desktops[0]
    if record.get("bundle_id") != profile.bundle_id or record.get("app_name") != profile.app_name:
        raise safety.SafetyError("Recorded desktop identity differs from the requested workspace app")
    stopped_exact = stop_desktop_record(cfg, record, wait_seconds=wait_seconds)
    if not stopped_exact:
        if record.get("desktop_record_state") == DESKTOP_RECORD_STATE_ATTEMPT:
            raise safety.SafetyError("Desktop launch attempt is unresolved; preserved for exact cleanup retry")
        raise safety.SafetyError("Desktop shutdown is incomplete; preserved for exact cleanup retry")
    _save_manifests(cfg, [entry for entry in records if entry is not record])


def launch_desktop_local(
    cfg: config.HarnessConfig,
    profile: desktop_profile.DesktopLocalProfile,
    *,
    run_sh: Path | None = None,
    wait_for_exit: bool = True,
    registration_timeout: float = 10.0,
    health_timeout: float = 20.0,
) -> dict[str, object]:
    """Replace and supervise only this workspace's proven named desktop app."""

    stop_desktop_for_relaunch(cfg, profile)
    _require_port_available_or_owned(cfg, "desktop", cfg.automation_port, label="automation")
    launch_token = secrets.token_urlsafe(32)
    signal_path = cfg.layout.state_root / "manifests" / "desktop-launch.signal"
    signal_path.unlink(missing_ok=True)
    attempt = DesktopLaunchAttempt(
        instance=cfg.instance,
        automation_port=cfg.automation_port,
        app_name=profile.app_name,
        bundle_id=profile.bundle_id,
        app_path=desktop_app_path(profile),
        executable_path=desktop_executable_path(profile),
        profile_root=desktop_profile_root(profile),
        state_root=cfg.layout.state_root,
        launch_token=launch_token,
        attempted_at=_now(),
    ).as_record()
    _replace_desktop_record(cfg, attempt)
    command_path = run_sh or cfg.repo_root / "desktop" / "macos" / "run.sh"
    env = desktop_profile.child_env(profile, parent=os.environ)
    env.update(
        {
            "OMI_DESKTOP_LAUNCH_TOKEN": launch_token,
            "OMI_DESKTOP_LAUNCH_SIGNAL_FILE": str(signal_path),
        }
    )
    try:
        subprocess.run(
            [str(command_path), "--no-wait"],
            cwd=command_path.parent,
            env=env,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        # A compile/package failure happens before run.sh writes its launch
        # signal. Clear that never-launched attempt so correcting source and
        # retrying is ordinary. If the signal exists or an exact token-bound
        # process already appeared, retain the evidence for safe cleanup.
        recovered = recover_desktop_record(cfg, attempt)
        if recovered == attempt and not signal_path.exists():
            _save_manifests(
                cfg,
                [entry for entry in _process_records(cfg) if entry.get("service") != "desktop"],
            )
        raise

    registration_deadline = time.time() + registration_timeout
    while True:
        try:
            record = register_desktop_launch(
                cfg,
                profile,
                signal_path=signal_path,
                launch_token=launch_token,
            )
            break
        except safety.SafetyError:
            if time.time() >= registration_deadline:
                raise
            time.sleep(0.1)

    health_deadline = time.time() + health_timeout
    while True:
        status, detail = desktop_record_status(cfg, record)
        if status == "healthy":
            record = bind_desktop_source_provenance(cfg, record)
            break
        if status == "stale/unowned" or time.time() >= health_deadline:
            try:
                stopped_exact = stop_desktop_record(cfg, record)
            except safety.SafetyError:
                raise
            if stopped_exact:
                _save_manifests(
                    cfg,
                    [entry for entry in _process_records(cfg) if entry.get("service") != "desktop"],
                )
            raise safety.SafetyError(f"Desktop launch did not become healthy: {status}: {detail}")
        time.sleep(0.2)

    if not wait_for_exit:
        return record

    interrupted = False
    stopped_exact = False
    previous_term_handler: object | None = None

    def interrupt_monitor(_signum: int, _frame: object) -> None:
        raise KeyboardInterrupt

    if hasattr(signal, "SIGTERM"):
        previous_term_handler = signal.signal(signal.SIGTERM, interrupt_monitor)
    try:
        while True:
            if _validated_desktop_process(cfg, record) is not None:
                time.sleep(0.5)
                continue
            successor_deadline = time.time() + registration_timeout
            while True:
                try:
                    recovered = recover_desktop_record(cfg, record)
                except DesktopSuccessorPending:
                    if time.time() >= successor_deadline:
                        return record
                    time.sleep(0.1)
                    continue
                if recovered != record:
                    record = recovered
                    break
                if time.time() >= successor_deadline:
                    return record
                time.sleep(0.1)
    except KeyboardInterrupt:
        interrupted = True
        stopped_exact = stop_desktop_record(cfg, record)
    finally:
        if previous_term_handler is not None:
            signal.signal(signal.SIGTERM, previous_term_handler)
        if stopped_exact:
            _save_manifests(
                cfg,
                [entry for entry in _process_records(cfg) if entry.get("service") != "desktop"],
            )
    if interrupted:
        print("desktop: stopped exact workspace app")
    return record


def _service_health(cfg: config.HarnessConfig, service: str) -> tuple[bool, str]:
    if service == "redis":
        if _port_open("127.0.0.1", cfg.redis_port):
            return True, "port-open"
        return False, "port-closed"
    if service == "firestore":
        return _http_ok(f"http://{cfg.firestore_host}/")
    if service == "auth":
        return _http_ok(f"http://{cfg.auth_host}/")
    if service == "backend":
        return _http_ok(f"{cfg.backend_url}/v1/health")
    return False, f"unknown service {service!r}"


def _owned_record_ports(record: dict[str, object]) -> tuple[int, ...]:
    owned_ports = record.get("owned_ports")
    if isinstance(owned_ports, dict):
        try:
            ports = tuple(sorted({int(port) for port in owned_ports.values()}))
        except (TypeError, ValueError):
            return ()
        return tuple(port for port in ports if 1 <= port <= 65535)
    try:
        port = int(record.get("port", -1))
    except (TypeError, ValueError):
        return ()
    return (port,) if 1 <= port <= 65535 else ()


def _capture_owned_listener_processes(
    cfg: config.HarnessConfig,
    record: dict[str, object],
) -> dict[str, object]:
    """Persist exact listener identity while supervisor lineage is still provable."""

    service = str(record.get("service", ""))
    pid = int(record.get("pid", -1))
    process_group = int(record.get("process_group", -1))
    if process_group != pid:
        raise safety.SafetyError(f"{service} process group no longer matches its recorded supervisor")
    safety.validate_owned_pid(pid, process_manifest=cfg.layout.process_manifest, service=service)
    captured: dict[int, dict[str, object]] = {}
    for port in _owned_record_ports(record):
        safety.validate_port_owner(
            port,
            pid=pid,
            port_manifest=cfg.layout.port_manifest,
            process_manifest=None,
            service=service,
        )
        for listener_pid in safety.listening_pids(port):
            if not safety.is_descendant_of(listener_pid, pid):
                raise safety.SafetyError(
                    f"{service} port {port} has foreign listener PID {listener_pid}; refusing supervisor signal"
                )
            process = safety.process_snapshot(listener_pid)
            if process is None:
                raise safety.SafetyError(f"Cannot snapshot {service} listener PID {listener_pid}")
            evidence = captured.setdefault(
                listener_pid,
                {
                    "pid": listener_pid,
                    "process_start": process.process_start,
                    "command_sha256": hashlib.sha256(process.command.encode()).hexdigest(),
                    "ports": [],
                },
            )
            ports = evidence["ports"]
            assert isinstance(ports, list)
            ports.append(port)
    prepared = dict(record)
    prepared["listener_processes"] = sorted(captured.values(), key=lambda evidence: int(evidence["pid"]))
    return prepared


def _validated_recorded_listeners(record: dict[str, object]) -> tuple[safety.ProcessSnapshot, ...]:
    evidence = record.get("listener_processes")
    if not isinstance(evidence, list):
        if any(safety.listening_pids(port) for port in _owned_record_ports(record)):
            raise safety.SafetyError("Owned service has live listeners but no pre-signal listener provenance")
        return ()
    by_pid: dict[int, dict[str, object]] = {}
    for item in evidence:
        if not isinstance(item, dict):
            raise safety.SafetyError("Owned service listener provenance is malformed")
        try:
            listener_pid = int(item["pid"])
            process_start = str(item["process_start"])
            command_sha256 = str(item["command_sha256"])
            ports = tuple(int(port) for port in item["ports"])
        except (KeyError, TypeError, ValueError):
            raise safety.SafetyError("Owned service listener provenance is malformed") from None
        if (
            listener_pid <= 0
            or not process_start
            or not safety.valid_process_fingerprint(process_start, command_sha256)
            or not ports
            or any(port not in _owned_record_ports(record) for port in ports)
        ):
            raise safety.SafetyError("Owned service listener provenance is malformed")
        by_pid[listener_pid] = item
    current_listener_pids = {
        listener_pid for port in _owned_record_ports(record) for listener_pid in safety.listening_pids(port)
    }
    validated: list[safety.ProcessSnapshot] = []
    for listener_pid in sorted(current_listener_pids):
        item = by_pid.get(listener_pid)
        process = safety.process_snapshot(listener_pid)
        if (
            item is None
            or process is None
            or not safety.matches_process_fingerprint(
                process,
                process_start=str(item["process_start"]),
                command_sha256=str(item["command_sha256"]),
            )
        ):
            raise safety.SafetyError(
                f"Listener PID {listener_pid} no longer matches its pre-signal ownership provenance"
            )
        validated.append(process)
    return tuple(validated)


def _signal_owned_supervisor(pid: int, service: str, sig: signal.Signals = signal.SIGINT) -> None:
    """Signal the supervisor once; it owns forwarding to its direct child."""

    try:
        os.kill(pid, sig)
        print(f"{service}: sent {sig.name} to supervisor PID {pid}")
    except ProcessLookupError:
        return
    except PermissionError as exc:
        raise safety.SafetyError(f"Cannot signal supervisor PID {pid}: {exc}") from exc


def _stop_owned_service_record(
    cfg: config.HarnessConfig,
    record: dict[str, object],
) -> None:
    service = str(record.get("service", ""))
    pid = int(record.get("pid", -1))
    prepared = record
    if safety.process_exists(pid):
        prepared = _capture_owned_listener_processes(cfg, record)
        current_records = [entry for entry in _process_records(cfg) if entry.get("service") != service]
        current_records.append(prepared)
        _save_manifests(cfg, current_records)
    for sig, wait_seconds in SERVICE_STOP_PHASES:
        supervisor_alive = safety.process_exists(pid)
        listeners = _validated_recorded_listeners(prepared)
        if not supervisor_alive and not listeners:
            return
        if supervisor_alive:
            safety.validate_owned_pid(pid, process_manifest=cfg.layout.process_manifest, service=service)
            _signal_owned_supervisor(pid, service, sig)
        else:
            for listener in listeners:
                try:
                    os.kill(listener.pid, sig)
                    print(f"{service}: sent {sig.name} to pre-proven orphan listener PID {listener.pid}")
                except ProcessLookupError:
                    continue
                except PermissionError as exc:
                    raise safety.SafetyError(f"Cannot signal {service} listener PID {listener.pid}: {exc}") from exc
        deadline = time.monotonic() + wait_seconds
        while time.monotonic() < deadline:
            if not safety.process_exists(pid) and not _validated_recorded_listeners(prepared):
                return
            time.sleep(0.2)
    if safety.process_exists(pid) or _validated_recorded_listeners(prepared):
        raise safety.SafetyError(f"{service} still has a supervisor or listener after exact shutdown")


def _stop_single_service(cfg: config.HarnessConfig, record: dict[str, object]) -> bool:
    service = str(record.get("service"))
    try:
        _stop_owned_service_record(cfg, record)
    except safety.SafetyError as exc:
        print(f"{service}: not stopped before restart: {exc}")
        return False
    remaining = [entry for entry in _process_records(cfg) if entry.get("service") != service]
    _save_manifests(cfg, remaining)
    return not any(entry.get("service") == service for entry in _process_records(cfg))


def _require_port_available_or_owned(
    cfg: config.HarnessConfig, service: str, port: int, *, label: str | None = None
) -> None:
    if not _port_open("127.0.0.1", port):
        return
    record = _service_record(cfg, service)
    if record is None:
        display_name = label or service
        raise RuntimeError(
            f"Port {port} for {display_name} is already in use by a foreign process. "
            "Stop it or set a separate local harness state/port before retrying."
        )
    supervisor_pid = int(record["pid"])
    safety.validate_port_owner(
        port,
        pid=supervisor_pid,
        port_manifest=cfg.layout.port_manifest,
        process_manifest=cfg.layout.process_manifest,
        service=service,
    )
    listeners = safety.listening_pids(port)
    foreign_listeners = tuple(pid for pid in listeners if not safety.is_descendant_of(pid, supervisor_pid))
    if foreign_listeners:
        rendered = ", ".join(str(pid) for pid in foreign_listeners)
        display_name = label or service
        raise RuntimeError(
            f"Port {port} for {display_name} has foreign listener PID(s) {rendered}; "
            f"none are descendants of recorded {service} supervisor PID {supervisor_pid}."
        )
    if not listeners:
        display_name = label or service
        raise RuntimeError(
            f"Port {port} for {display_name} is open but its listener PID cannot be proven; refusing to proceed."
        )


def _workspace_port_owners(cfg: config.HarnessConfig) -> tuple[tuple[str, str, int], ...]:
    """Return every listener in the workspace contract and its process owner."""

    return (
        ("backend", "backend", cfg.backend_port),
        ("firestore", "firestore", cfg.firestore_port),
        ("auth", "firestore", cfg.auth_port),
        ("redis", "redis", cfg.redis_port),
        ("automation", "desktop", cfg.automation_port),
        ("firestore.websocket", "firestore", cfg.firestore_websocket_port),
        ("firebase.hub", "firestore", cfg.firebase_hub_port),
        ("firebase.logging", "firestore", cfg.firebase_logging_port),
        ("firebase.ui", "firestore", cfg.firebase_ui_port),
    )


def _require_workspace_ports_available_or_owned(cfg: config.HarnessConfig) -> None:
    for label, service, port in _workspace_port_owners(cfg):
        _require_port_available_or_owned(cfg, service, port, label=label)


def _http_ok(url: str, timeout: float = 1.0, headers: dict[str, str] | None = None) -> tuple[bool, str]:
    try:
        request = urllib.request.Request(url, headers=headers or {})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status < 500, f"HTTP {response.status}"
    except urllib.error.HTTPError as exc:
        return exc.code < 500, f"HTTP {exc.code}"
    except Exception as exc:  # noqa: BLE001 - health output should be actionable, not typed
        return False, str(exc)


def _which(name: str) -> bool:
    return shutil.which(name) is not None


def _python_importable(module: str) -> bool:
    return (
        subprocess.run(
            [sys.executable, "-c", f"import {module}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode
        == 0
    )


def prerequisite_report(
    cfg: config.HarnessConfig,
    provider_report: providers.ProviderPreflight | None = None,
) -> tuple[list[str], list[str]]:
    missing: list[str] = []
    warnings: list[str] = []
    if not _which("node"):
        missing.append("node (required by Firebase emulator CLI)")
    if not (_which("firebase") or _which("npx")):
        missing.append(
            "firebase-tools CLI or npx (install with npm install, npm install -g firebase-tools, or use npx)"
        )
    if not _which("java"):
        missing.append("java runtime (required by Firestore emulator)")
    if not _which("redis-server"):
        missing.append("redis-server (required for local Redis on loopback)")
    if not (cfg.repo_root / "firebase.json").is_file():
        missing.append("firebase.json at repo root")
    if not (cfg.repo_root / "firestore.rules").is_file():
        missing.append("firestore.rules at repo root")
    if not (cfg.repo_root / "firestore.indexes.json").is_file():
        missing.append("firestore.indexes.json at repo root")
    if not (cfg.repo_root / "backend" / "main.py").is_file():
        missing.append("backend/main.py")
    if not _python_importable("uvicorn"):
        missing.append("Python package uvicorn (install backend requirements before starting backend)")
    provider_report = provider_report or _current_provider_report(cfg)
    missing.extend(provider_report.missing)
    warnings.extend(provider_report.warnings)
    if cfg.provider_mode == "offline":
        warnings.append(
            "PROVIDER_MODE=offline: external-provider credentials are stripped from child processes; only fake-backed provider paths are available."
        )
    return missing, warnings


def print_config(cfg: config.HarnessConfig) -> None:
    print(f"instance: {cfg.instance}")
    print(f"provider_mode: {cfg.provider_mode}")
    print(f"state_root: {cfg.layout.state_root}")
    print(f"firebase_project: {cfg.project_id}")
    print(f"firestore_database: {cfg.database_id}")
    print(f"firestore_emulator: {cfg.firestore_host}")
    print(f"firebase_auth_emulator: {cfg.auth_host}")
    print(f"redis: {cfg.redis_host}:{cfg.redis_port}")
    print(f"backend: {cfg.backend_url}")
    print(f"automation: 127.0.0.1:{cfg.automation_port}")
    print(f"firestore_websocket: 127.0.0.1:{cfg.firestore_websocket_port}")
    print(f"firebase_hub: 127.0.0.1:{cfg.firebase_hub_port}")
    print(f"firebase_logging: 127.0.0.1:{cfg.firebase_logging_port}")
    print(f"firebase_ui: 127.0.0.1:{cfg.firebase_ui_port}")


def print_provider_status(
    cfg: config.HarnessConfig,
    report: providers.ProviderPreflight | None = None,
    *,
    show_current_sources: bool = True,
) -> providers.ProviderPreflight:
    parsed = config.parse_secrets_file(cfg) if show_current_sources else None
    report = report or _current_provider_report(cfg)
    print("provider_status:")
    for line in providers.status_lines(report):
        print(f"  {line}")
    if parsed is not None and parsed.ignored_keys:
        print("secrets_file_ignored_keys:")
        for key in parsed.ignored_keys:
            print(f"  - {key} (harness injects this; remove from backend/.env.local-dev)")
    if parsed is not None and parsed.sources:
        print("provider_credential_sources:")
        for key in sorted(parsed.sources):
            if key == "PROVIDER_MODE":
                print(f"  {key}: {parsed.sources[key]}")
            elif key in config.CORE_PROVIDER_ENV:
                print(f"  {key}: {parsed.sources[key]}")
    return report


def _git_metadata(repo_root: Path) -> dict[str, object]:
    def run_git(args: list[str]) -> str:
        result = subprocess.run(
            ["git", *args], cwd=repo_root, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5
        )
        return result.stdout.strip() if result.returncode == 0 else "unknown"

    return {"commit": run_git(["rev-parse", "HEAD"]), "dirty": bool(run_git(["status", "--porcelain"]))}


def _summary_path(cfg: config.HarnessConfig) -> Path:
    return cfg.layout.reports_dir / "local-emulator-session-summary.json"


def build_session_summary(cfg: config.HarnessConfig, provider_report: providers.ProviderPreflight) -> dict[str, object]:
    profiles = synthetic_profiles.load_manifest(cfg)
    config_digest = _load_json(cfg.layout.config_digest_path, {})
    endpoints = {
        "firestore": cfg.firestore_host,
        "firebase_auth": cfg.auth_host,
        "redis": f"{cfg.redis_host}:{cfg.redis_port}",
        "backend": cfg.backend_url,
        "automation": f"127.0.0.1:{cfg.automation_port}",
        "firestore_websocket": f"127.0.0.1:{cfg.firestore_websocket_port}",
        "firebase_hub": f"127.0.0.1:{cfg.firebase_hub_port}",
        "firebase_logging": f"127.0.0.1:{cfg.firebase_logging_port}",
        "firebase_ui": f"127.0.0.1:{cfg.firebase_ui_port}",
    }
    return {
        "schema_version": 1,
        "evidence_class": "LOCAL_EMULATOR_DEV",
        "activation_eligible": False,
        "watermark": "NOT_ACTIVATION_EVIDENCE",
        "generated_at": _now(),
        "instance": cfg.instance,
        "state_root": str(cfg.layout.state_root),
        "firebase_project_id": cfg.project_id,
        "firestore_database_id": cfg.database_id,
        "provider_mode": cfg.provider_mode,
        "enabled_external_providers": list(provider_report.enabled_external_providers),
        "credential_fingerprints": dict(provider_report.fingerprints),
        "offline_fake_sources": dict(provider_report.offline_fake_sources),
        "local_endpoints": endpoints,
        "selected_user": profiles.get("selected_user"),
        "seeded_users": synthetic_profiles.profile_aliases(cfg),
        "git": _git_metadata(cfg.repo_root),
        "config_digest": _json_digest(config_digest) if config_digest else None,
        "session_budget": {
            "session_usd": providers.DEFAULT_SESSION_BUDGET_USD,
            "day_usd": providers.DEFAULT_DAILY_BUDGET_USD,
            "concurrency": providers.DEFAULT_MAX_CONCURRENCY,
        },
        "external_provider_call_summary": {
            "instrumented": False,
            "placeholder": "Provider broker policy is present; live per-call accounting is not wired in this manual-QA slice.",
        },
        "protected_state_digest": {
            "computed": False,
            "before_digest": None,
            "after_digest": None,
            "placeholder": "Protected-collection before/after digests are not computed unless a live emulator readback instrumenter is added.",
        },
        "manual_qa": {
            "framing": "Exploratory product-use workflow; not a deterministic long-lived pass/fail product test suite.",
            "status": "not_asserted_by_harness",
            "notes": [],
        },
        "non_claims": [
            "Not DEV_CLOUD_PROOF.",
            "Not production, dev-cloud, IAM, deployed index, telemetry sink, rollback, or activation proof.",
            "Does not imply production or dev-cloud activation eligibility.",
        ],
    }


def write_session_summary(cfg: config.HarnessConfig, provider_report: providers.ProviderPreflight) -> Path:
    path = _summary_path(cfg)
    _write_json(path, build_session_summary(cfg, provider_report))
    return path


def cmd_check(args: argparse.Namespace) -> int:
    requested = config.load_config(_repo_root(), create_layout=False)
    try:
        cfg, requested_provider_mode = active_runtime_config(requested)
        provider_report = _runtime_provider_report(cfg)
    except RuntimeError as exc:
        print(f"dev-check failed: {exc}")
        return 1
    missing, warnings = prerequisite_report(cfg, provider_report)
    print("Intentive local dev harness prerequisite check")
    print_config(cfg)
    if requested_provider_mode is not None:
        print(f"requested_provider_mode: {requested_provider_mode} (active stack takes precedence)")
    print_provider_status(cfg, provider_report, show_current_sources=False)
    if warnings:
        print("\nWarnings:")
        for item in warnings:
            print(f"  - {item}")
    if missing:
        print("\nMissing prerequisites:")
        for item in missing:
            print(f"  - {item}")
        return 1
    print("\nAll required prerequisites for this mode are present.")
    return 0


def _prepend_pythonpath(env: dict[str, str], *entries: Path) -> None:
    values = [str(path) for path in entries]
    if existing := env.get("PYTHONPATH"):
        values.append(existing)
    env["PYTHONPATH"] = os.pathsep.join(values)


def _start_process(
    cfg: config.HarnessConfig,
    service: str,
    command: list[str],
    *,
    cwd: Path,
    log_name: str,
    port: int,
    owned_ports: dict[str, int] | None = None,
    env: dict[str, str] | None = None,
) -> None:
    existing = _service_record(cfg, service)
    if existing is not None:
        healthy, detail = _service_health(cfg, service)
        if healthy:
            print(f"{service}: already recorded as running")
            return
        print(f"{service}: recorded process unhealthy ({detail}); restarting")
        if not _stop_single_service(cfg, existing):
            raise safety.SafetyError(f"{service} exact shutdown was incomplete; refusing replacement start")
    _require_port_available_or_owned(cfg, service, port)
    marker = _marker(cfg, service)
    log_path = cfg.layout.logs_dir / log_name
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("ab")
    child_env = config.child_env_for(cfg) if env is None else env
    python_paths = [cfg.repo_root / "scripts" / "dev-harness"]
    if service == "backend":
        python_paths.append(cfg.repo_root / "backend")
    _prepend_pythonpath(child_env, *python_paths)
    supervised = [
        sys.executable,
        "-m",
        "dev_harness.supervise",
        "--marker",
        marker,
        "--service",
        service,
        "--",
        *command,
    ]
    proc = subprocess.Popen(
        supervised, cwd=str(cwd), env=child_env, stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True
    )
    records = [record for record in _process_records(cfg) if record.get("service") != service]
    records.append(
        {
            "service": service,
            "pid": proc.pid,
            "process_group": proc.pid,
            "port": port,
            "owned_ports": owned_ports or {service: port},
            "endpoint": f"127.0.0.1:{port}",
            "log": str(log_path),
            "ownership_marker": marker,
            "started_at": _now(),
            "command": command,
        }
    )
    _save_manifests(cfg, records)
    print(f"{service}: started pid={proc.pid} log={log_path}")


def _firebase_command(cfg: config.HarnessConfig) -> list[str]:
    config_path = cfg.layout.services_dir / "firebase" / "firebase.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        payload = json.loads((cfg.repo_root / "firebase.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Cannot load firebase.json for harness: {exc}") from exc
    emulators = payload.setdefault("emulators", {})
    for name, port in (("firestore", cfg.firestore_port), ("auth", cfg.auth_port)):
        emulator = emulators.setdefault(name, {})
        emulator["host"] = "127.0.0.1"
        emulator["port"] = port
    emulators["firestore"]["websocketPort"] = cfg.firestore_websocket_port
    emulators["hub"] = {"host": "127.0.0.1", "port": cfg.firebase_hub_port}
    emulators["logging"] = {"host": "127.0.0.1", "port": cfg.firebase_logging_port}
    emulators["ui"] = {"enabled": True, "host": "127.0.0.1", "port": cfg.firebase_ui_port}
    firestore = payload.setdefault("firestore", {})
    firestore["rules"] = str(cfg.repo_root / "firestore.rules")
    firestore["indexes"] = str(cfg.repo_root / "firestore.indexes.json")
    _write_json(config_path, payload)
    base = ["firebase"] if _which("firebase") else ["npx", "firebase-tools"]
    return [
        *base,
        "emulators:start",
        "--config",
        str(config_path),
        "--only",
        "firestore,auth",
        "--project",
        cfg.project_id,
        "--import",
        str(cfg.layout.services_dir / "firebase-export"),
        "--export-on-exit",
        str(cfg.layout.services_dir / "firebase-export"),
    ]


# Infrastructure services (firestore, auth, redis) start first so the
# Python backend can connect to them immediately on boot.  The brief settle delay
# prevents a port-binding race on resource-constrained runners (e.g. M1 Studio
# under qualification load) where the backend starts before the emulator has
# finished binding its port.
_INFRA_SETTLE_DELAY = 2.0


def _start_infrastructure(cfg: config.HarnessConfig) -> None:
    cfg.layout.logs_dir.mkdir(parents=True, exist_ok=True)
    _start_process(
        cfg,
        "firestore",
        _firebase_command(cfg),
        cwd=cfg.repo_root,
        log_name="firebase-emulators.log",
        port=cfg.firestore_port,
        owned_ports={
            "firestore": cfg.firestore_port,
            "auth": cfg.auth_port,
            "firestore.websocket": cfg.firestore_websocket_port,
            "firebase.hub": cfg.firebase_hub_port,
            "firebase.logging": cfg.firebase_logging_port,
            "firebase.ui": cfg.firebase_ui_port,
        },
    )
    redis_dir = cfg.layout.services_dir / "redis"
    redis_dir.mkdir(parents=True, exist_ok=True)
    _start_process(
        cfg,
        "redis",
        [
            "redis-server",
            "--bind",
            "127.0.0.1",
            "--port",
            str(cfg.redis_port),
            "--dir",
            str(redis_dir),
            "--save",
            "",
            "--appendonly",
            "no",
        ],
        cwd=cfg.repo_root,
        log_name="redis.log",
        port=cfg.redis_port,
    )


def _uvicorn_app_command(
    cfg: config.HarnessConfig,
    *,
    app_target: str,
    offline_app_target: str,
    port: int,
) -> list[str]:
    target = app_target
    command = [sys.executable, "-m", "uvicorn"]
    if cfg.provider_mode == "offline":
        target = offline_app_target
    command.extend([target, "--host", "127.0.0.1", "--port", str(port)])
    return command


def _start_app_services(cfg: config.HarnessConfig) -> None:
    """Start the canonical backend after infrastructure is settling."""
    _start_process(
        cfg,
        "backend",
        _uvicorn_app_command(
            cfg,
            app_target="main:app",
            offline_app_target="testing.e2e.offline_backend_app:app",
            port=cfg.backend_port,
        ),
        cwd=cfg.repo_root / "backend",
        log_name="backend.log",
        port=cfg.backend_port,
        env=config.child_env_for(cfg),
    )


def _start_services(cfg: config.HarnessConfig) -> None:
    _require_workspace_ports_available_or_owned(cfg)
    _start_infrastructure(cfg)
    # Give infrastructure services a brief head start so the Python backend can
    # bind connections to Redis and Firestore immediately on boot.
    # Without this, on a loaded runner the backend may retry connections during
    # its startup window, extending boot time beyond the health-check deadline.
    time.sleep(_INFRA_SETTLE_DELAY)
    _start_app_services(cfg)


# Per-service health-check deadlines (seconds).  The Python backend needs the
# longest window: it imports heavy ML/NLP modules and initialises connections to
# every infrastructure service.  On an M1 Studio runner under qualification load,
# 45 s (the old flat deadline shared across *all* services) is not enough.
_HEALTH_TIMEOUTS: dict[str, float] = {
    "firestore": 45.0,
    "auth": 45.0,
    "backend": 90.0,
    "redis": 30.0,
}


def _wait_health(
    cfg: config.HarnessConfig,
    *,
    timeout: float | None = None,
) -> list[str]:
    """Wait for all harness services to become healthy.

    Each service has its own deadline (see ``_HEALTH_TIMEOUTS``) measured from
    the moment the wait begins.  If a recorded process dies before its deadline,
    the service is marked unhealthy immediately instead of polling uselessly.
    Pass ``timeout`` to override the backend deadline for backwards-compat callers.
    """
    checks = {
        "firestore": (f"http://{cfg.firestore_host}/", None),
        "auth": (f"http://{cfg.auth_host}/", None),
        "backend": (f"{cfg.backend_url}/v1/health", None),
        "redis": (None, None),  # port-based check
    }
    pending = dict(checks)
    start = time.time()
    # Per-service deadlines; ``timeout`` overrides the backend deadline only.
    deadlines: dict[str, float] = {}
    for service in pending:
        base = _HEALTH_TIMEOUTS.get(service, 45.0)
        if timeout is not None and service == "backend":
            base = timeout
        deadlines[service] = start + base
    failures: dict[str, str] = {}
    process_records = {r["service"]: r for r in _process_records(cfg)}
    while pending:
        now = time.time()
        # Expire services whose per-service deadline has passed.
        for service in list(pending):
            if now >= deadlines[service]:
                url = pending[service][0]
                failures.setdefault(service, f"not healthy after {deadlines[service] - start:.0f}s at {url}")
                pending.pop(service)
        if not pending:
            break
        for service, (url, headers) in list(pending.items()):
            # Fail fast if the process died — no point polling a dead service.
            record = process_records.get(service)
            if record:
                pid_val = int(record.get("pid", -1))
                if not safety.process_exists(pid_val):
                    failures[service] = f"process exited (pid={pid_val}); check log: {record.get('log', '?')}"
                    pending.pop(service)
                    print(f"{service}: {failures[service]}")
                    continue
            if service == "redis":
                if _port_open("127.0.0.1", cfg.redis_port):
                    print("redis: healthy (port-open)")
                    pending.pop(service)
                continue
            ok, detail = _http_ok(url, headers=headers)
            if ok:
                print(f"{service}: healthy ({detail})")
                failures.pop(service, None)
                pending.pop(service)
            else:
                failures[service] = detail
        if pending:
            time.sleep(0.75)
    return [f"{service}: {failures[service]}" for service in sorted(failures)]


def cmd_up(args: argparse.Namespace) -> int:
    cfg = config.load_config(_repo_root(), create_layout=True)
    provider_report = _current_provider_report(cfg)
    try:
        active_mode = prepare_provider_mode_for_start(cfg)
    except RuntimeError as exc:
        print(f"dev-up failed: {exc}")
        return 1
    missing, warnings = prerequisite_report(cfg, provider_report)
    print("Intentive local dev harness startup")
    print_config(cfg)
    print_provider_status(cfg, provider_report)
    for item in warnings:
        print(f"warning: {item}")
    if missing:
        print("\nCannot start; missing prerequisites:")
        for item in missing:
            print(f"  - {item}")
        return 1
    config_digest = _config_digest(cfg, provider_report)
    try:
        _start_services(cfg)
        failures = _wait_health(cfg)
    except Exception as exc:  # noqa: BLE001
        print(f"dev-up failed: {exc}")
        return 1
    if failures:
        print("\nHealth checks failed:")
        for failure in failures:
            print(f"  - {failure}")
        print(f"Inspect logs with: make dev-logs OMI_LOCAL_STATE_ROOT={cfg.layout.state_root.parent}")
        return 1
    if active_mode is None:
        _write_json(cfg.layout.config_digest_path, config_digest)
    try:
        synthetic_profiles.seed_profiles(cfg)
        print("synthetic desktop profiles: ready")
    except Exception as exc:  # noqa: BLE001
        print(f"synthetic desktop profile seed failed: {exc}")
        return 1
    print("\nLocal dev harness is up.")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    requested = config.load_config(_repo_root(), create_layout=False)
    try:
        cfg, requested_provider_mode = active_runtime_config(requested)
        provider_report = _runtime_provider_report(cfg)
    except RuntimeError as exc:
        print(f"dev-status failed: {exc}")
        return 1
    print("Intentive local dev harness status")
    print_config(cfg)
    if requested_provider_mode is not None:
        print(f"requested_provider_mode: {requested_provider_mode} (active stack takes precedence)")
    print_provider_status(cfg, provider_report, show_current_sources=False)
    if cfg.provider_mode == "offline":
        print(
            "offline_hint: PROVIDER_MODE=offline active; external provider credentials are stripped from child processes"
        )
    else:
        print(
            "offline_hint: run with PROVIDER_MODE=offline for hermetic fake providers and no external provider credentials"
        )
    if not cfg.layout.sentinel_path.is_file():
        print("sentinel: missing (run make dev-up or make dev-reset to initialize harness-owned state)")
    else:
        safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
        print("sentinel: ok")
    profiles = synthetic_profiles.load_manifest(cfg)
    print("\nSynthetic desktop profiles:")
    if profiles:
        print(f"  selected_user: {profiles.get('selected_user')}")
        users = synthetic_profiles.profile_aliases(cfg)
        print(f"  seeded_users: {', '.join(users) if users else 'unknown'}")
    else:
        print("  profiles: none (run make dev-init, then make dev-up)")
        print("  seeded_users: none")
    print(f"  session_summary_path: {_summary_path(cfg)}")
    if getattr(args, "write_summary", False):
        path = write_session_summary(cfg, provider_report)
        print(f"  session_summary_written: {path}")
    print("\nProcesses:")
    records = _process_records(cfg)
    if not records:
        print("  - none recorded")
    for record in records:
        pid = int(record.get("pid", -1))
        service = str(record.get("service"))
        if service == "desktop":
            try:
                recovered = recover_desktop_record(cfg, record)
            except safety.SafetyError as exc:
                state, detail = "stale/unowned", str(exc)
            else:
                record = recovered
                pid = int(record.get("pid", -1))
                state, detail = desktop_record_status(cfg, record)
            print(f"  - desktop: pid={pid} state={state} detail={detail}")
            continue
        alive = safety.process_exists(pid)
        health = "not checked"
        port = int(record.get("port", 0) or 0)
        if port:
            health = "port-open" if _port_open("127.0.0.1", port) else "port-closed"
        print(f"  - {service}: pid={pid} alive={alive} {health} log={record.get('log')}")
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    requested = config.load_config(_repo_root(), create_layout=False)
    try:
        cfg, _ = active_runtime_config(requested)
        provider_report = _runtime_provider_report(cfg)
    except RuntimeError as exc:
        print(f"Cannot write session summary: {exc}")
        return 1
    if not cfg.layout.sentinel_path.is_file():
        print("Cannot write session summary: harness sentinel is missing (run make dev-up or make dev-reset first)")
        return 1
    safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
    path = write_session_summary(cfg, provider_report)
    print(path)
    return 0


def _stop_owned(cfg: config.HarnessConfig) -> bool:
    records = _process_records(cfg)
    desktop_records = [record for record in records if record.get("service") == "desktop"]
    group_records = [record for record in records if record.get("service") != "desktop"]
    stopped = True
    desktop_stopped = True
    for record in desktop_records:
        try:
            if stop_desktop_record(cfg, record):
                print(f"desktop: sent SIGTERM to exact PID {record.get('pid')}")
            else:
                desktop_stopped = False
        except safety.SafetyError as exc:
            print(f"desktop: not stopped: {exc}")
            stopped = False
            desktop_stopped = False
    for record in group_records:
        service = str(record.get("service"))
        try:
            _stop_owned_service_record(cfg, record)
        except safety.SafetyError as exc:
            print(f"{service}: not stopped: {exc}")
            stopped = False
    remaining = _process_records(cfg)
    if desktop_stopped:
        remaining = [record for record in remaining if record.get("service") != "desktop"]
    _save_manifests(cfg, remaining)
    return stopped and not _process_records(cfg)


def cmd_down(args: argparse.Namespace) -> int:
    cfg = config.load_config(_repo_root(), create_layout=False)
    if not cfg.layout.sentinel_path.is_file():
        print("No harness-owned state exists; nothing to stop.")
        return 0
    safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
    if not _stop_owned(cfg):
        print("dev-down incomplete; preserved ownership evidence for safe retry or inspection.")
        return 1
    return 0


def _clear_state(cfg: config.HarnessConfig) -> None:
    safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
    for child in ("manifests", "logs", "reports", "services", "files"):
        target = cfg.layout.state_root / child
        if target.exists():
            safety.validate_destructive_target(target, state_root=cfg.layout.state_root, repo_root=cfg.repo_root)
            shutil.rmtree(target)
    safety.create_state_layout(cfg.repo_root, cfg.instance, {"OMI_LOCAL_STATE_ROOT": str(cfg.layout.state_root.parent)})


def cmd_reset(args: argparse.Namespace) -> int:
    cfg = config.load_config(_repo_root(), create_layout=True)
    print(f"Resetting harness-owned state only: {cfg.layout.state_root}")
    safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
    if not _stop_owned(cfg):
        print("Reset refused because exact shutdown was incomplete; ownership evidence was preserved.")
        return 1
    _clear_state(cfg)
    print("Reset complete.")
    return 0


def cmd_logs(args: argparse.Namespace) -> int:
    cfg = config.load_config(_repo_root(), create_layout=False)
    print(f"logs_dir: {cfg.layout.logs_dir}")
    for path in sorted(cfg.layout.logs_dir.glob("*.log")) if cfg.layout.logs_dir.is_dir() else []:
        print(f"\n==> {path} <==")
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[-80:]
        for line in lines:
            print(line)
    return 0


def cmd_qualification_lease(args: argparse.Namespace) -> int:
    repo_root = _repo_root()
    if args.lease_action == "acquire":
        lease = qualification.acquire(
            repo_root=repo_root,
            lease_id=args.lease_id,
            owner_pid=args.owner_pid,
            port_offset=args.port_offset,
            retained_runs=args.retained_runs,
            retention_age_seconds=args.retention_age_seconds,
        )
        print(json.dumps(lease, sort_keys=True))
        return 0
    if args.lease_action == "release":
        qualification.release(
            repo_root=repo_root,
            lease_id=args.lease_id,
            token=args.token,
            retained_runs=args.retained_runs,
            retention_age_seconds=args.retention_age_seconds,
        )
        return 0
    if args.lease_action == "preflight-fault-cleanup":
        qualification.preflight_fault_cleanup(
            repo_root=repo_root,
            lease_id=args.lease_id,
            token=args.token,
            result_path=Path(args.result),
        )
        return 0
    raise AssertionError(f"Unexpected qualification lease action {args.lease_action!r}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="dev-harness")
    sub = parser.add_subparsers(dest="command", required=True)
    for name, func in {
        "check": cmd_check,
        "up": cmd_up,
        "status": cmd_status,
        "summary": cmd_summary,
        "down": cmd_down,
        "reset": cmd_reset,
        "logs": cmd_logs,
    }.items():
        command = sub.add_parser(name)
        if name == "status":
            command.add_argument("--write-summary", action="store_true", default=False)
        command.set_defaults(func=func)
    lease = sub.add_parser("qualification-lease", help="Acquire or safely release a local qualification stack lease")
    lease_sub = lease.add_subparsers(dest="lease_action", required=True)
    acquire = lease_sub.add_parser("acquire")
    acquire.add_argument("--lease-id", required=True)
    acquire.add_argument("--owner-pid", required=True, type=int)
    acquire.add_argument("--port-offset", required=True, type=int)
    acquire.add_argument("--retained-runs", type=int, default=qualification.DEFAULT_RETAINED_RUNS)
    acquire.add_argument("--retention-age-seconds", type=int, default=qualification.DEFAULT_RETENTION_MAX_AGE_SECONDS)
    acquire.set_defaults(func=cmd_qualification_lease)
    release = lease_sub.add_parser("release")
    release.add_argument("--lease-id", required=True)
    release.add_argument("--token", required=True)
    release.add_argument("--retained-runs", type=int, default=qualification.DEFAULT_RETAINED_RUNS)
    release.add_argument("--retention-age-seconds", type=int, default=qualification.DEFAULT_RETENTION_MAX_AGE_SECONDS)
    release.set_defaults(func=cmd_qualification_lease)
    fault_preflight = lease_sub.add_parser(
        "preflight-fault-cleanup",
        help="Validate and reclaim the exact lease-owned disposable fault listener",
    )
    fault_preflight.add_argument("--lease-id", required=True)
    fault_preflight.add_argument("--token", required=True)
    fault_preflight.add_argument("--result", required=True)
    fault_preflight.set_defaults(func=cmd_qualification_lease)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = build_parser().parse_args(list(argv) if argv is not None else None)
    try:
        return int(args.func(args))
    except (safety.SafetyError, qualification.QualificationLeaseError) as exc:
        print(f"Safety check failed: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
