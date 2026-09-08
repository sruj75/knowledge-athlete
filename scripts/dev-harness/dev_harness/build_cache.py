"""Place each worktree's generated SwiftPM output on an explicit cache volume."""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path


def prepare(repo: Path, cache_root: Path) -> Path:
    repo = repo.resolve(strict=True)
    package = repo / "desktop/macos/Desktop"
    if not (package / "Package.swift").is_file():
        raise ValueError("Not an Intentive Swift package worktree")
    if not cache_root.is_absolute() or not cache_root.parent.is_dir() or cache_root.is_symlink():
        raise ValueError("Cache root must be absolute with an existing parent (mount the cache volume first)")
    # UID and exact checkout path prevent sharing mutable SwiftPM build state.
    identity = f"{os.getuid()}:{repo}"
    key = hashlib.sha256(identity.encode()).hexdigest()[:24]
    owner = cache_root / key
    target = owner / "swiftpm"
    link = package / ".build"
    marker = owner / "worktree.txt"
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.readlink() != target:
            raise ValueError(
                "Existing .build is preserved; inspect it before opting this worktree into external caching"
            )
    if owner.exists() and (not marker.is_file() or marker.read_text() != identity + "\n"):
        raise ValueError("Cache owner does not match this user and worktree")
    owner.mkdir(parents=True, exist_ok=True)
    marker.write_text(identity + "\n")
    target.mkdir(exist_ok=True)
    if not link.is_symlink():
        link.symlink_to(target, target_is_directory=True)
    return target


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: build_cache.py <worktree> <cache root>")
        print(prepare(Path(sys.argv[1]), Path(sys.argv[2])))
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2) from None
