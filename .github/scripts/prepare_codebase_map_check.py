#!/usr/bin/env python3
"""Provision viewer packages and Chromium only for a manifest-selected CI check."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from pr_preflight import changed_files
from run_checks import detect_platform, load_manifest, resolve_checks


def prepare(root: Path, files: list[str]) -> None:
    manifest = load_manifest(root / ".github/checks-manifest.yaml")
    checks = resolve_checks(manifest, files, "ci", platform=detect_platform())
    if not any(check.id == "codebase-map" for check in checks):
        print("Codebase map check not selected; dependency preparation skipped.")
        return

    app = root / "tools/codebase-map"
    subprocess.run(["npm", "ci", "--no-audit", "--no-fund"], cwd=app, check=True)
    subprocess.run(
        ["npm", "exec", "--no", "--", "playwright", "install", "--with-deps", "chromium"],
        cwd=app,
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        prepare(root, changed_files(root, args.base, "HEAD"))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: codebase map dependency preparation: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
