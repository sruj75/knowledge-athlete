#!/usr/bin/env python3
"""Hold every AGENTS.md to a size ratchet.

Agent guides are loaded into agent context: the root file in every session for
every task, each component guide whenever an agent works in that area. Every
line is paid for repeatedly, by every agent, forever. Unbounded guides are how a
repo ends up with rules nobody reads and pointers nobody maintains.

Budgets are a ratchet. When a file shrinks, lower its budget in the same PR.
Never raise a budget to admit detail that has a home one level down:

  root AGENTS.md        cross-component rules and the index, nothing else
  CLAUDE.md            pointer to the same entrypoint
Detailed authored rules live in openwiki/INSTRUCTIONS.md. OpenWiki pages explain
source and executable contracts.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

# path -> (max_lines, max_bytes). Ratchet down; never up.
BUDGETS: dict[str, tuple[int, int]] = {
    "AGENTS.md": (40, 3_200),
    "CLAUDE.md": (8, 600),
}

SKIP_PARTS = {"node_modules", ".build", ".git", ".context", ".venv", "vendor"}

FAILURE_HINT = (
    "Agent entrypoints are loaded into context every session.\n"
    "Move detailed rules into openwiki/INSTRUCTIONS.md and link the relevant section.\n"
    "Do not raise a budget to admit detail that has a narrower owner."
)


def measure(data: bytes) -> tuple[int, int]:
    text = data.decode("utf-8")
    lines = text.count("\n") + (0 if data.endswith(b"\n") else 1)
    return lines, len(data)


def check_file(path: Path, budget: tuple[int, int], label: str) -> list[str]:
    max_lines, max_bytes = budget
    lines, size = measure(path.read_bytes())
    errors = []
    if lines > max_lines:
        errors.append(f"{label}: {lines} lines exceeds budget of {max_lines}")
    if size > max_bytes:
        errors.append(f"{label}: {size} bytes exceeds budget of {max_bytes}")
    return errors


def discover(repo: Path) -> list[Path]:
    return sorted(p for name in ("AGENTS.md", "CLAUDE.md") for p in repo.rglob(name) if not SKIP_PARTS.intersection(p.relative_to(repo).parts))


def self_test() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "AGENTS.md"

        f.write_text("# ok\n")
        assert check_file(f, (10, 100), "t") == [], "lean file must pass"

        f.write_text("x\n" * 11)
        assert any("lines" in e for e in check_file(f, (10, 10_000), "t")), "over-lines must fail"

        f.write_text("y" * 101)
        assert any("bytes" in e for e in check_file(f, (10_000, 100), "t")), "over-bytes must fail"


def main() -> int:
    self_test()
    repo = Path(__file__).resolve().parents[2]

    errors: list[str] = []
    found = {str(p.relative_to(repo)) for p in discover(repo)}

    # Every AGENTS.md must carry a budget, so a new guide cannot land unbounded.
    for rel in sorted(found - BUDGETS.keys()):
        errors.append(
            f"{rel}: new AGENTS.md has no budget. Add one to BUDGETS in "
            f"{Path(__file__).name}, set to its current size."
        )
    for rel in sorted(BUDGETS.keys() - found):
        errors.append(f"{rel}: has a budget but no longer exists. Remove its entry.")

    for rel in sorted(found & BUDGETS.keys()):
        errors.extend(check_file(repo / rel, BUDGETS[rel], rel))

    if errors:
        print("AGENTS.md size ratchet failed:\n", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print(f"\n{FAILURE_HINT}", file=sys.stderr)
        return 1

    print(f"ok: {len(found)} AGENTS.md files within budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
