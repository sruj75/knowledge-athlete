#!/usr/bin/env python3
"""Require visible review context when instructions or enforcement change.

PR #120 exposed an imported merge preference losing its fork qualification and
later becoming a GitHub restriction. This checks disclosure, not whether an
authorization is genuine; reviewers must verify the cited original decision.
"""

from __future__ import annotations

import argparse
import fnmatch
import re
import subprocess
from pathlib import Path

POLICY_PATHS = (
    "AGENTS.md",
    "**/AGENTS.md",
    "CLAUDE.md",
    "**/CLAUDE.md",
    "SKILL.md",
    "**/SKILL.md",
    "openwiki/INSTRUCTIONS.md",
    ".conductor/settings*.toml",
    ".github/workflows/*",
    ".github/actions/*",
    ".github/checks-manifest.yaml",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/scripts/*",
    "scripts/pr-preflight",
    "scripts/preflight*",
    "scripts/pre-commit*",
    "scripts/pre-push*",
    "scripts/failure-class",
    ".pre-commit-config.yaml",
    "Makefile",
)
FIELDS = ("Policy-Source", "Policy-Scope", "Policy-Effect", "Policy-Qualifications")
PLACEHOLDER = re.compile(r"(?:none|n/?a|todo|tbd|\.\.\.|<[^>]*>|\[[^]]*\])", re.I)


def policy_paths(
    root: Path, base: str, head: str, changed_files: Path | None = None
) -> list[str]:
    # Deleted sources must remain visible when an instruction is moved/renamed.
    result = subprocess.run(
        ["git", "diff", "--name-only", "--no-renames", "-z", f"{base}...{head}"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    paths = set(result.stdout.split("\0"))
    # The local manifest runner also selects dirty/untracked files. Retain
    # those inputs without losing deleted rename sources from the Git diff.
    if changed_files is not None:
        paths.update(changed_files.read_text(encoding="utf-8").splitlines())
        if head == "HEAD":
            worktree = subprocess.run(
                ["git", "diff", "--name-only", "--no-renames", "-z", "HEAD"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            paths.update(worktree.stdout.split("\0"))
    return sorted(
        path
        for path in paths
        if path and any(fnmatch.fnmatchcase(path, pattern) for pattern in POLICY_PATHS)
    )


def review_errors(body: str) -> list[str]:
    visible = re.sub(r"<!--.*?(?:-->|$)", "", body, flags=re.S)
    visible = re.sub(r"(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1[^\n]*(?:\n|$)", "", visible)
    sections = re.split(r"(?m)^##[ \t]+Policy changes[ \t]*$", visible)
    if len(sections) != 2:
        return ["include exactly one '## Policy changes' section"]
    section = re.split(r"(?m)^#{1,2}[ \t]+", sections[1], maxsplit=1)[0]
    errors = []
    for field in FIELDS:
        values = re.findall(rf"(?m)^{field}:[ \t]*([^\n]*)$", section)
        if len(values) != 1:
            errors.append(f"include exactly one {field}: field")
            continue
        value = values[0].strip().strip("`*_ ")
        if not value or PLACEHOLDER.fullmatch(value):
            errors.append(f"replace the empty/placeholder {field}: with review context")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--changed-files", type=Path)
    parser.add_argument("--pr-body-file", type=Path, required=True)
    args = parser.parse_args()
    try:
        paths = policy_paths(args.root, args.base, args.head, args.changed_files)
        if not paths:
            print("Policy review: no instruction or enforcement paths changed.")
            return 0
        errors = review_errors(args.pr_body_file.read_text(encoding="utf-8"))
    except (OSError, subprocess.CalledProcessError) as error:
        detail = (
            error.stderr
            if isinstance(error, subprocess.CalledProcessError)
            else str(error)
        )
        print(f"FAIL: policy review inputs unavailable: {detail}")
        return 1
    print("Policy review paths:\n" + "\n".join(f"  {path}" for path in paths))
    if errors:
        print("FAIL: " + "; ".join(errors))
        print(
            "Cite the original user decision and its date/link, affected scope, before/after "
            "effect (or why unchanged), and preserved/changed qualifications."
        )
        return 1
    print(
        "Policy review disclosure present; reviewers must verify its source and authorization."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
