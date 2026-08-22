"""
Server-driven config for toggling subscription-surface visibility per
platform and app version.

Stored in Firestore so the flag can be flipped without a redeploy:

  Collection: app_review_config
  Document ID: ios | android | macos
  Fields:
    hidden_versions: list[str]   # e.g. ["1.0.531", "1.0.531+607"]
    reviewer_uids:   list[str]   # specific UIDs to always hide for

A version in `hidden_versions` matches the app version using the same
semantic-vs-build comparison moved here when the announcements product was removed, so an
entry like "1.0.531" matches every build of that semantic version.
"""

from typing import Any, Optional, cast

from database._client import db
from database.cache import get_memory_cache

_CACHE_KEY_PREFIX = "app_review_config:"
_CACHE_TTL_SECONDS = 60  # short so flag flips propagate within a minute


def _parse_version(version: str) -> tuple[tuple[int, int, int], int, bool]:
    if not version:
        return (0, 0, 0), 0, False
    semantic, separator, build_text = version.lstrip('v').partition('+')
    try:
        parts = tuple(int(part) for part in semantic.split('.'))
    except ValueError:
        return (0, 0, 0), 0, False
    padded = (parts + (0, 0, 0))[:3]
    try:
        build = int(build_text) if separator else 0
    except ValueError:
        build = 0
    return cast(tuple[int, int, int], padded), build, bool(separator)


def compare_versions(left: str, right: str) -> int:
    """Compare semantic versions, treating a missing build as a wildcard."""

    left_semantic, left_build, left_has_build = _parse_version(left)
    right_semantic, right_build, right_has_build = _parse_version(right)
    if left_semantic != right_semantic:
        return -1 if left_semantic < right_semantic else 1
    if not left_has_build or not right_has_build or left_build == right_build:
        return 0
    return -1 if left_build < right_build else 1


def _fetch_review_config(platform: str) -> dict[str, Any]:
    doc = db.collection("app_review_config").document(platform).get()
    if not getattr(doc, "exists", False):
        return {}
    raw: object = doc.to_dict()
    return cast(dict[str, Any], raw) if isinstance(raw, dict) else {}


def get_review_config(platform: str) -> dict[str, Any]:
    """Return the review-config doc for a platform, cached for 60s."""
    cache_key = f"{_CACHE_KEY_PREFIX}{platform}"
    fetched = get_memory_cache().get_or_fetch(cache_key, lambda: _fetch_review_config(platform), ttl=_CACHE_TTL_SECONDS)
    return cast(dict[str, Any], fetched) if isinstance(fetched, dict) else {}


_SUPPORTED_PLATFORMS = {"ios", "macos"}


def should_hide_subscription_ui(uid: str, platform: Optional[str], app_version: Optional[str]) -> bool:
    """True when subscription surfaces should be hidden for this caller."""
    normalized = (platform or "").lower()
    if normalized not in _SUPPORTED_PLATFORMS:
        return False

    cfg = get_review_config(normalized) or {}

    if uid:
        reviewer_uids_raw = cfg.get("reviewer_uids")
        reviewer_uids: list[object] = (
            cast(list[object], reviewer_uids_raw) if isinstance(reviewer_uids_raw, list) else []
        )
        if uid in [r for r in reviewer_uids if isinstance(r, str)]:
            return True

    if app_version:
        hidden_versions_raw = cfg.get("hidden_versions")
        hidden_versions: list[object] = (
            cast(list[object], hidden_versions_raw) if isinstance(hidden_versions_raw, list) else []
        )
        for hidden in [v for v in hidden_versions if isinstance(v, str)]:
            if compare_versions(app_version, hidden) == 0:
                return True

    return False
