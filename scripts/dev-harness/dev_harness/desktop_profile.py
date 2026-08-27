"""Desktop local profile resolution and static safety scanning.

This module is the harness-owned source of truth for the macOS desktop
``Intentive Dev`` local harness profile. It intentionally resolves a launch
configuration without reading provider-bearing ``.env`` files and can be
exercised on Linux for static verification when the native macOS build/launch
path is unavailable.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Mapping
from urllib.parse import urlparse

from . import config, safety, synthetic_profiles

LOCAL_APP_NAME = "Intentive Dev"
LOCAL_DISPLAY_NAME = "Intentive Dev"
LOCAL_BUNDLE_ID = "com.heyintentive.intentive.dev"
LOCAL_URL_SCHEME = "heyintentive-dev"
LOCAL_STORAGE_NAME = "Intentive Dev"
LOCAL_NAMED_BUNDLE_PREFIX = "omi-"
LOCAL_FIREBASE_API_KEY = "local-firebase-auth-emulator-api-key"
LOCAL_FIREBASE_APP_ID = "1:000000000000:ios:heyintentive-dev-local"
LOCAL_FIREBASE_CLIENT_ID = "local-heyintentive-dev.apps.localhost"
LOCAL_FIREBASE_GCM_SENDER_ID = "000000000000"
LOCAL_FIREBASE_PLIST = "GoogleService-Info-Local.plist"
LOCAL_ACCESS_GROUP = ""
LOCAL_PROFILE_OMI_DEV_BLOCKED = (
    "local profile cannot target Intentive Dev (com.heyintentive.intentive.dev); "
    "use a named omi- bundle (e.g. DESKTOP_APP_NAME=omi-memory make desktop-run-local)"
)


def _slugify_identifier(value: str) -> str:
    lowered = value.lower()
    slug = re.sub(r"[^a-z0-9]+", "-", lowered).strip("-")
    return re.sub(r"-+", "-", slug)


def _resolve_local_app_name(env: Mapping[str, str] | None = None) -> str:
    source = os.environ if env is None else env
    raw = str(source.get("OMI_APP_NAME", "") or source.get("DESKTOP_APP_NAME", "")).strip()
    return raw or LOCAL_APP_NAME


def _local_bundle_id(app_name: str) -> str:
    if app_name == LOCAL_APP_NAME:
        return LOCAL_BUNDLE_ID
    slug = _slugify_identifier(app_name)
    if not slug:
        raise ValueError(f"OMI_APP_NAME {app_name!r} must contain at least one letter or number")
    return f"com.heyintentive.intentive.dev.{slug}"


def _local_url_scheme(app_name: str) -> str:
    if app_name == LOCAL_APP_NAME:
        return LOCAL_URL_SCHEME
    return f"heyintentive-{_slugify_identifier(app_name)}"


def _local_storage_name(app_name: str) -> str:
    if app_name == LOCAL_APP_NAME:
        return LOCAL_STORAGE_NAME
    return app_name


PROHIBITED_ENDPOINT_PATTERNS = (
    re.compile(r"https://api\.omi\.me", re.IGNORECASE),
    re.compile(r"https://api\.omiapi\.com", re.IGNORECASE),
    re.compile(r"https://desktop-backend-[a-z0-9-]+\.a\.run\.app", re.IGNORECASE),
    re.compile(r"https://desktop-backend-[a-z0-9-]+-uc\.a\.run\.app", re.IGNORECASE),
    re.compile(r"trycloudflare\.com", re.IGNORECASE),
)
PROHIBITED_PROJECT_PATTERNS = (
    re.compile(r"based-hardware", re.IGNORECASE),
    re.compile(r"demo-memory", re.IGNORECASE),
)
PROVIDER_CREDENTIAL_PATTERNS = (
    re.compile(r"\b(?:sk|sk-proj)-[A-Za-z0-9_-]{12,}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{20,}\b"),
    re.compile(r"\b(?:OPENAI|DEEPGRAM|ANTHROPIC|GROQ|GEMINI|GOOGLE)_?(?:API_)?KEY\s*="),
    re.compile(r"\b(?:ACCESS_TOKEN|AUTH_TOKEN|SECRET)\s*="),
)
_PROVIDER_ENV_NAMES = (
    "OPENAI_API_KEY",
    "DEEPGRAM_API_KEY",
    "ANTHROPIC_API_KEY",
    "GROQ_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
)


@dataclass(frozen=True)
class DesktopLocalProfile:
    app_name: str
    display_name: str
    bundle_id: str
    url_scheme: str
    preferences_domain: str
    keychain_access_group: str
    application_support_dir: str
    caches_dir: str
    firebase_project_id: str
    firebase_database_id: str
    firebase_auth_emulator_host: str
    firebase_api_key: str
    firebase_app_id: str
    firebase_client_id: str
    firebase_gcm_sender_id: str
    firebase_plist: str
    backend_url: str
    selected_user: str
    selected_user_email: str
    selected_user_display_name: str
    selected_user_password: str
    default_user: str
    seeded_users: tuple[str, ...]
    state_root: str
    session_summary_path: str
    env: Mapping[str, str]

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2, sort_keys=True) + "\n"


def _is_loopback_url(raw: str) -> bool:
    parsed = urlparse(raw)
    if parsed.scheme not in {"http", "ws"} or not parsed.netloc:
        return False
    return safety.is_loopback_host(parsed.netloc)


def resolve_profile(
    cfg: config.HarnessConfig,
    *,
    user: str,
    seeded_users: Iterable[str],
    env: Mapping[str, str] | None = None,
) -> DesktopLocalProfile:
    users = tuple(sorted(set(str(item) for item in seeded_users)))
    payload = synthetic_profiles.profile_payload(cfg, user)
    email = payload.get("email", f"{user}@local.heyintentive.invalid")
    display_name = payload.get("display_name", f"Synthetic {user}")
    password = payload.get("password", f"{user}-local-password-030")
    backend_url = cfg.backend_url
    app_name = _resolve_local_app_name(env)
    bundle_id = _local_bundle_id(app_name)
    url_scheme = _local_url_scheme(app_name)
    storage_name = _local_storage_name(app_name)
    env = {
        "OMI_DESKTOP_LOCAL_PROFILE": "1",
        "OMI_HARNESS_INSTANCE": cfg.instance,
        "OMI_SEED_FROM_CANONICAL_DEV": "0",
        "OMI_SKIP_BACKEND": "1",
        "OMI_SKIP_TUNNEL": "1",
        "OMI_PYTHON_API_URL": backend_url,
        "OMI_LOCAL_PROFILE_STORAGE_NAME": storage_name,
        "OMI_LOCAL_AUTH_USER": user,
        "OMI_LOCAL_AUTH_EMAIL": email,
        "OMI_LOCAL_AUTH_PASSWORD": password,
        "OMI_LOCAL_AUTH_DISPLAY_NAME": display_name,
        "FIREBASE_AUTH_EMULATOR_HOST": cfg.auth_host,
        "FIREBASE_PROJECT_ID": cfg.project_id,
        "FIREBASE_AUTH_PROJECT_ID": cfg.project_id,
        "FIRESTORE_DATABASE_ID": cfg.database_id,
        "FIREBASE_API_KEY": LOCAL_FIREBASE_API_KEY,
    }
    if app_name != LOCAL_APP_NAME:
        env["OMI_APP_NAME"] = app_name
        env["OMI_ENABLE_LOCAL_AUTOMATION"] = os.environ.get("OMI_ENABLE_LOCAL_AUTOMATION", "1")
        if os.environ.get("OMI_AUTOMATION_PORT"):
            env["OMI_AUTOMATION_PORT"] = os.environ["OMI_AUTOMATION_PORT"]
    return DesktopLocalProfile(
        app_name=app_name,
        display_name=app_name if app_name != LOCAL_APP_NAME else LOCAL_DISPLAY_NAME,
        bundle_id=bundle_id,
        url_scheme=url_scheme,
        preferences_domain=bundle_id,
        keychain_access_group=LOCAL_ACCESS_GROUP,
        application_support_dir=(
            f"~/Library/Application Support/Intentive Dev"
            if app_name == LOCAL_APP_NAME
            else f"~/Library/Application Support/Intentive Dev Bundles/{bundle_id}"
        ),
        caches_dir=(
            f"~/Library/Caches/Intentive Dev"
            if app_name == LOCAL_APP_NAME
            else f"~/Library/Caches/Intentive Dev Bundles/{bundle_id}"
        ),
        firebase_project_id=cfg.project_id,
        firebase_database_id=cfg.database_id,
        firebase_auth_emulator_host=cfg.auth_host,
        firebase_api_key=LOCAL_FIREBASE_API_KEY,
        firebase_app_id=LOCAL_FIREBASE_APP_ID,
        firebase_client_id=LOCAL_FIREBASE_CLIENT_ID,
        firebase_gcm_sender_id=LOCAL_FIREBASE_GCM_SENDER_ID,
        firebase_plist=LOCAL_FIREBASE_PLIST,
        backend_url=backend_url,
        selected_user=user,
        selected_user_email=email,
        selected_user_display_name=display_name,
        selected_user_password=password,
        default_user="local_default_user",
        seeded_users=users,
        state_root=str(cfg.layout.state_root),
        session_summary_path=str(cfg.layout.reports_dir / "local-emulator-session-summary.json"),
        env=env,
    )


def validate_profile(profile: DesktopLocalProfile) -> list[str]:
    errors: list[str] = []
    if profile.bundle_id == LOCAL_BUNDLE_ID:
        errors.append(LOCAL_PROFILE_OMI_DEV_BLOCKED)
    if profile.bundle_id in {"com.heyintentive.intentive", "com.heyintentive.intentive.beta"}:
        errors.append("local profile must not use production bundle")
    if profile.app_name == LOCAL_APP_NAME:
        if profile.bundle_id != LOCAL_BUNDLE_ID:
            errors.append("local profile app/bundle identity drifted")
        if profile.url_scheme != LOCAL_URL_SCHEME:
            errors.append("local URL scheme drifted")
    else:
        if not profile.app_name.lower().startswith(LOCAL_NAMED_BUNDLE_PREFIX):
            errors.append("named local harness bundles must use an omi- prefix")
        expected_bundle = _local_bundle_id(profile.app_name)
        if profile.bundle_id != expected_bundle:
            errors.append(f"named bundle id must be {expected_bundle}")
        expected_scheme = _local_url_scheme(profile.app_name)
        if profile.url_scheme != expected_scheme:
            errors.append(f"named bundle URL scheme must be {expected_scheme}")
    if profile.firebase_project_id != safety.DEFAULT_LOCAL_FIREBASE_PROJECT_ID:
        errors.append("local profile must use demo-heyintentive-local only")
    if profile.firebase_database_id != safety.DEFAULT_FIRESTORE_DATABASE_ID:
        errors.append("local profile must use Firestore database (default)")
    if not _is_loopback_url(profile.backend_url):
        errors.append(f"backend_url must be loopback http/ws, got {profile.backend_url!r}")
    if not safety.is_loopback_host(profile.firebase_auth_emulator_host):
        errors.append("Firebase Auth emulator host must be loopback")
    text = profile.to_json()
    for regex in (*PROHIBITED_ENDPOINT_PATTERNS, *PROHIBITED_PROJECT_PATTERNS, *PROVIDER_CREDENTIAL_PATTERNS):
        if regex.search(text):
            errors.append(f"resolved profile matched prohibited pattern: {regex.pattern}")
    for key in _PROVIDER_ENV_NAMES:
        if key in profile.env:
            errors.append(f"provider credential env {key} must not be in desktop local profile")
    return errors


def scan_text(name: str, text: str) -> list[str]:
    errors: list[str] = []
    for regex in (*PROHIBITED_ENDPOINT_PATTERNS, *PROHIBITED_PROJECT_PATTERNS, *PROVIDER_CREDENTIAL_PATTERNS):
        if regex.search(text):
            errors.append(f"{name}: prohibited pattern {regex.pattern}")
    return errors


def scan_paths(paths: Iterable[Path]) -> list[str]:
    errors: list[str] = []
    for path in paths:
        if not path.exists():
            continue
        if path.is_dir():
            candidates = [p for p in path.rglob("*") if p.is_file()]
        else:
            candidates = [path]
        for candidate in candidates:
            if candidate.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".icns", ".dylib"}:
                continue
            try:
                text = candidate.read_text(encoding="utf-8", errors="ignore")
            except OSError as exc:
                errors.append(f"{candidate}: cannot read for scan: {exc}")
                continue
            errors.extend(scan_text(str(candidate), text))
    return errors


def write_resolved_profile(profile: DesktopLocalProfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(profile.to_json(), encoding="utf-8")
