"""Install locations shared by named Dev launchers and exact-owner shutdown."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Mapping


def dev_app_path(app_name: str, *, root: str | Path | None = None) -> Path:
    """Allow only Dev identities in the system or current user's Applications."""
    slug = re.sub(r"[^a-z0-9]+", "-", app_name.lower()).strip("-")
    if (
        not app_name
        or any(character in app_name for character in ("/", "\\", "\n", "\r", "\x00"))
        or (app_name != "Intentive Dev" and not slug.startswith("omi-"))
    ):
        raise ValueError("Dev install requires Intentive Dev or an omi- named app")
    directory = Path(root) if root is not None else Path("/Applications")
    if directory not in (Path("/Applications"), Path.home() / "Applications") or directory.is_symlink():
        raise ValueError("Dev app root must be /Applications or the current user's ~/Applications, without a symlink")
    return directory / f"{app_name}.app"


def configured_app_path(app_name: str, env: Mapping[str, str] | None = None) -> Path:
    source = os.environ if env is None else env
    return dev_app_path(app_name, root=source.get("OMI_DEV_APP_ROOT") or None)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: desktop_paths.py <Dev app name>")
        print(configured_app_path(sys.argv[1]))
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2) from None
