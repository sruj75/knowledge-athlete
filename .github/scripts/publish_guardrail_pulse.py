#!/usr/bin/env python3
"""Publish one guardrail history append from a disposable main checkout."""

from __future__ import annotations

import argparse
from datetime import date, datetime, timezone
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

HISTORY = ".github/guardrail-pulse-history.jsonl"


def git(root: Path, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, check=True
    ).stdout


def require_history_file(root: Path, ref: str) -> None:
    tree = git(root, "ls-tree", ref, "--", HISTORY)
    mode = (root / HISTORY).lstat().st_mode
    if not tree.startswith(b"100644 blob ") or not stat.S_ISREG(mode) or mode & 0o111:
        raise ValueError("history must keep its existing regular-file mode 100644")


def require_payload(payload: object, recorded_at: str) -> None:
    if (
        not isinstance(payload, dict)
        or set(payload) != {"date", "metrics"}
        or payload["date"] != recorded_at
    ):
        raise ValueError("invalid report row identity")
    metrics = payload["metrics"]
    if not isinstance(metrics, dict) or not metrics:
        raise ValueError("invalid report metrics")
    for name, metric in metrics.items():
        if (
            not isinstance(name, str)
            or not name
            or not isinstance(metric, dict)
            or set(metric) != {"count", "baseline"}
        ):
            raise ValueError("invalid report metric shape")
        if any(type(value) is not int or value < 0 for value in metric.values()):
            raise ValueError("invalid report metric count")


def require_candidate(root: Path, base: str, candidate: str, expected: bytes) -> None:
    if git(root, "rev-parse", "HEAD").decode().strip() != candidate:
        raise ValueError(
            "candidate checkout advanced unexpectedly; preserving local commits"
        )
    if git(root, "rev-list", "--parents", "-n", "1", candidate).decode().split() != [
        candidate,
        base,
    ]:
        raise ValueError(
            "candidate must be one report commit directly after fetched main"
        )
    if (
        git(root, "diff", "--no-renames", "--name-status", "-z", base, candidate)
        != f"M\0{HISTORY}\0".encode()
    ):
        raise ValueError("candidate must change only the existing report history")
    require_history_file(root, candidate)
    if git(root, "show", f"{candidate}:{HISTORY}") != expected:
        raise ValueError("candidate must contain exactly the validated report append")
    if git(
        root, "status", "--porcelain=v1", "--untracked-files=all", "--ignored=matching"
    ):
        raise ValueError("candidate checkout must remain clean")


def publish(root: Path, recorded_at: str) -> object:
    if git(root, "symbolic-ref", "--short", "HEAD").strip() != b"main":
        raise ValueError("publisher requires the main branch")
    if git(
        root, "status", "--porcelain=v1", "--untracked-files=all", "--ignored=matching"
    ):
        raise ValueError(
            "publisher requires a clean disposable checkout, including index and untracked files"
        )
    git(root, "fetch", "origin", "refs/heads/main:refs/remotes/origin/main")
    if git(root, "rev-list", "origin/main..HEAD"):
        raise ValueError("publisher main contains unpublished commits")
    git(root, "reset", "--hard", "origin/main")
    for attempt in range(1, 4):
        base = git(root, "rev-parse", "HEAD").decode().strip()
        require_history_file(root, base)
        previous = git(root, "show", f"{base}:{HISTORY}")
        if previous and not previous.endswith(b"\n"):
            raise ValueError("existing history must end at a JSONL row boundary")
        generated = subprocess.run(
            [
                sys.executable,
                str(root / ".github/scripts/guardrail_pulse.py"),
                "--root",
                str(root),
                "--json",
                "--record",
                "--date",
                recorded_at,
            ],
            cwd=root,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            capture_output=True,
            check=True,
        )
        payload = json.loads(generated.stdout)
        require_payload(payload, recorded_at)
        require_history_file(root, base)
        if git(
            root,
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all",
            "--ignored=matching",
        ) != (f" M {HISTORY}\0".encode()):
            raise ValueError(
                "generator may only modify the unstaged report history file"
            )
        expected = previous + (json.dumps(payload, sort_keys=True) + "\n").encode()
        if (root / HISTORY).read_bytes() != expected:
            raise ValueError(
                "history must append exactly one expected report row without changing existing bytes"
            )
        if git(root, "rev-parse", "HEAD").decode().strip() != base:
            raise ValueError("generator changed the candidate commit baseline")
        git(root, "add", "--", HISTORY)
        git(root, "commit", "-m", "chore: record weekly guardrail baseline pulse")
        candidate = git(root, "rev-parse", "HEAD").decode().strip()
        require_candidate(root, base, candidate, expected)
        try:
            git(root, "push", "origin", f"{candidate}:refs/heads/main")
            return payload
        except subprocess.CalledProcessError:
            require_candidate(root, base, candidate, expected)
            git(root, "fetch", "origin", "refs/heads/main:refs/remotes/origin/main")
            remote = git(root, "rev-parse", "origin/main").decode().strip()
            if remote == candidate:
                return payload
            if remote == base:
                raise
            if git(root, "rev-list", f"{remote}..{base}"):
                raise ValueError(
                    "main history changed unexpectedly; refusing publication retry"
                )
            if attempt == 3:
                raise ValueError(
                    "main kept changing; report publication exhausted three attempts"
                )
            print(
                f"Main advanced during report publication; regenerating attempt {attempt + 1}/3.",
                file=sys.stderr,
            )
            git(root, "reset", "--hard", remote)
    raise AssertionError("unreachable publication attempt")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--date", default=datetime.now(timezone.utc).date().isoformat())
    args = parser.parse_args()
    try:
        date.fromisoformat(args.date)
        print(json.dumps(publish(args.root.resolve(), args.date), sort_keys=True))
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: guardrail report publication: {exc}", file=sys.stderr)
        if isinstance(exc, subprocess.CalledProcessError):
            for output in (exc.stdout, exc.stderr):
                if output:
                    print(output.decode(errors="replace"), file=sys.stderr, end="")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
