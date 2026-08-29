#!/usr/bin/env python3
"""Fail closed unless a release targets the separately approved API origin."""

from __future__ import annotations

import os
from urllib.parse import urlsplit


INHERITED_HOSTS = ("omi.me", "omiapi.com", "basedhardware.com")


def clean_https_origin(value: str, *, name: str) -> str:
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise ValueError(f"{name} is not a valid URL") from exc
    hostname = (parsed.hostname or "").lower().rstrip(".")
    if (
        value != value.strip()
        or parsed.scheme.lower() != "https"
        or not hostname
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError(f"{name} must be one clean HTTPS origin")
    if any(hostname == inherited or hostname.endswith(f".{inherited}") for inherited in INHERITED_HOSTS):
        raise ValueError(f"{name} must not use inherited provider infrastructure")
    return f"https://{hostname}"


def validate(candidate: str, approved: str) -> None:
    if not approved:
        raise ValueError("separately approved production API origin is missing")
    candidate_origin = clean_https_origin(candidate, name="INTENTIVE_PRODUCTION_API_URL")
    approved_origin = clean_https_origin(approved, name="INTENTIVE_APPROVED_PRODUCTION_API_ORIGIN")
    if candidate_origin != approved_origin or candidate.rstrip("/") != approved.rstrip("/"):
        raise ValueError("production API URL does not match the separately approved release origin")


def main() -> int:
    try:
        validate(
            os.environ.get("INTENTIVE_PRODUCTION_API_URL", ""),
            os.environ.get("INTENTIVE_APPROVED_PRODUCTION_API_ORIGIN", ""),
        )
    except ValueError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
