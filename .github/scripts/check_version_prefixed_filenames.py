#!/usr/bin/env python3
"""Reject version-prefixed source filenames outside their version package."""

from __future__ import annotations

import re
import subprocess
import sys
from collections.abc import Iterable
from pathlib import PurePosixPath

ISSUE_URL = "https://github.com/BasedHardware/omi/issues/9443"
VERSIONED_FILENAME = re.compile(r"^(?P<version>v[0-9]+)_.+\.(?:py|swift|ts|rs)$")

GRANDFATHERED_VIOLATIONS: set[str] = set()


def is_versioned_filename(path: str) -> bool:
    return bool(VERSIONED_FILENAME.fullmatch(PurePosixPath(path).name))


def is_in_versioned_package(path: str) -> bool:
    match = VERSIONED_FILENAME.fullmatch(PurePosixPath(path).name)
    return bool(match and match.group("version") in PurePosixPath(path).parts[:-1])


def violations(paths: Iterable[str]) -> list[str]:
    return sorted(
        path
        for path in paths
        if is_versioned_filename(path) and not is_in_versioned_package(path) and path not in GRANDFATHERED_VIOLATIONS
    )


def tracked_paths() -> list[str]:
    return subprocess.check_output(["git", "ls-files"], text=True).splitlines()


def main() -> int:
    invalid_paths = violations(tracked_paths())
    if not invalid_paths:
        print("OK: no new version-prefixed source filenames outside version packages.")
        return 0

    print(f"FAIL: version goes in the package path, not the filename — see {ISSUE_URL}.")
    for path in invalid_paths:
        print(f"  - {path}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
