"""Neutral synthetic Auth/profile identities for the local desktop harness."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Mapping
from urllib.parse import quote

from . import config, safety

PROFILE_MANIFEST = "synthetic-desktop-profiles.json"


@dataclass(frozen=True)
class SyntheticProfile:
    alias: str
    email: str
    display_name: str
    password: str


PROFILES = (
    SyntheticProfile(
        "local_default_user",
        "local_default_user@local.omi.invalid",
        "Synthetic Default",
        "local_default_user-local-password-030",
    ),
    SyntheticProfile("alice", "alice@local.omi.invalid", "Synthetic Alice", "alice-local-password-030"),
    SyntheticProfile("bob", "bob@local.omi.invalid", "Synthetic Bob", "bob-local-password-030"),
)


def manifest_path(cfg: config.HarnessConfig) -> Path:
    return cfg.layout.state_root / "manifests" / PROFILE_MANIFEST


def _payload(*, resolved_uids: Mapping[str, str] | None = None) -> dict[str, object]:
    resolved = resolved_uids or {}
    users = []
    for profile in PROFILES:
        user = asdict(profile)
        if profile.alias in resolved:
            user["resolved_uid"] = resolved[profile.alias]
        users.append(user)
    return {
        "schema_version": 1,
        "selected_user": "alice",
        "users": users,
        "local_only": True,
        "synthetic": True,
    }


def initialize_manifest(cfg: config.HarnessConfig) -> Path:
    path = manifest_path(cfg)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(_payload(), indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def load_manifest(cfg: config.HarnessConfig) -> dict[str, object]:
    path = manifest_path(cfg)
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def profile_aliases(cfg: config.HarnessConfig) -> list[str]:
    payload = load_manifest(cfg)
    users = payload.get("users", [])
    if not isinstance(users, list):
        return []
    return sorted(str(user["alias"]) for user in users if isinstance(user, dict) and isinstance(user.get("alias"), str))


def profile_payload(cfg: config.HarnessConfig, alias: str) -> dict[str, str]:
    users = load_manifest(cfg).get("users", [])
    if not isinstance(users, list):
        return {}
    for user in users:
        if isinstance(user, dict) and user.get("alias") == alias:
            return {str(key): str(value) for key, value in user.items() if value is not None}
    return {}


def _request_json(method: str, url: str, payload: Mapping[str, object]) -> tuple[int, str]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return int(response.status), response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return int(error.code), error.read().decode("utf-8", "replace")


def _ensure_auth_user(cfg: config.HarnessConfig, profile: SyntheticProfile) -> str:
    signup_url = f"http://{cfg.auth_host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local-harness"
    status, body = _request_json(
        "POST",
        signup_url,
        {
            "email": profile.email,
            "displayName": profile.display_name,
            "password": profile.password,
            "emailVerified": True,
            "disabled": False,
            "returnSecureToken": True,
        },
    )
    if status >= 400 and "EMAIL_EXISTS" not in body:
        raise RuntimeError(f"Auth emulator profile seed failed for {profile.alias}: HTTP {status} {body[:200]}")

    signin_url = (
        f"http://{cfg.auth_host}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-harness"
    )
    status, body = _request_json(
        "POST",
        signin_url,
        {"email": profile.email, "password": profile.password, "returnSecureToken": True},
    )
    if status >= 400:
        raise RuntimeError(f"Auth emulator profile lookup failed for {profile.alias}: HTTP {status} {body[:200]}")
    payload = json.loads(body)
    uid = payload.get("localId")
    if not isinstance(uid, str) or not uid:
        raise RuntimeError(f"Auth emulator returned no uid for {profile.alias}")
    return uid


def _firestore_value(value: object) -> dict[str, object]:
    if isinstance(value, bool):
        return {"booleanValue": value}
    return {"stringValue": str(value)}


def _write_profile(cfg: config.HarnessConfig, profile: SyntheticProfile, uid: str) -> None:
    encoded_uid = quote(uid, safe="")
    database_id = quote(cfg.database_id, safe="")
    url = (
        f"http://{cfg.firestore_host}/v1/projects/{cfg.project_id}/databases/{database_id}"
        f"/documents/users/{encoded_uid}"
    )
    fields = {
        "uid": uid,
        "email": profile.email,
        "display_name": profile.display_name,
        "synthetic": True,
        "local_harness": True,
    }
    status, body = _request_json(
        "PATCH",
        url,
        {"fields": {key: _firestore_value(value) for key, value in fields.items()}},
    )
    if status >= 400:
        raise RuntimeError(f"Firestore emulator profile seed failed for {profile.alias}: HTTP {status} {body[:200]}")


def seed_profiles(cfg: config.HarnessConfig) -> Path:
    safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
    resolved: dict[str, str] = {}
    for profile in PROFILES:
        uid = _ensure_auth_user(cfg, profile)
        _write_profile(cfg, profile, uid)
        resolved[profile.alias] = uid
    path = manifest_path(cfg)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(_payload(resolved_uids=resolved), indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def _repo_root() -> Path:
    return config.repo_root_from(Path.cwd())


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="synthetic-profiles")
    parser.add_argument("action", choices=("init", "seed"))
    args = parser.parse_args(list(argv) if argv is not None else None)
    cfg = config.load_config(_repo_root(), create_layout=True)
    path = initialize_manifest(cfg) if args.action == "init" else seed_profiles(cfg)
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
