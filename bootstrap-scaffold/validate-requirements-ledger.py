#!/usr/bin/env python3
"""Validate the requirements scratchpad's index, sections, and closure state."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import re
import sys


DEFAULT_DOCUMENT = Path(__file__).with_name("requirements-challenge.md")
LEDGER_MARKER = "## Requirement ledger"
GRAPH_MARKER = "## Dependency graph and closure status"
SECTION_RE = re.compile(r"^## (IR-\d+)\b.*$", re.MULTILINE)
STALE_GRAPH_RE = re.compile(
    r"\b(?:ACTIVE REVIEW|CHILDREN OPEN|OPEN CHILD|UNRESOLVED|NOT REVIEWED|REOPENED)\b",
    re.IGNORECASE,
)


def split_table_row(line: str) -> list[str]:
    """Split a Markdown row while preserving escaped literal pipes."""

    return [cell.strip() for cell in re.split(r"(?<!\\)\|", line)[1:-1]]


def duplicate_values(values: list[str]) -> list[str]:
    return sorted(value for value, count in Counter(values).items() if count > 1)


def main() -> int:
    document = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DOCUMENT
    text = document.read_text(encoding="utf-8")
    errors: list[str] = []

    try:
        ledger_start = text.index(LEDGER_MARKER)
        graph_start = text.index(GRAPH_MARKER, ledger_start)
    except ValueError as exc:
        print(f"FAIL: required document marker is missing: {exc}", file=sys.stderr)
        return 1

    ledger_rows: list[list[str]] = []
    for line_number, line in enumerate(text[ledger_start:graph_start].splitlines(), start=1):
        if not line.startswith("| IR-"):
            continue
        cells = split_table_row(line)
        if len(cells) != 4:
            errors.append(f"ledger relative line {line_number}: expected 4 cells, found {len(cells)}")
            continue
        ledger_rows.append(cells)

    ledger_ids = [row[0] for row in ledger_rows]
    duplicate_rows = duplicate_values(ledger_ids)
    if duplicate_rows:
        errors.append(f"duplicate ledger IDs: {', '.join(duplicate_rows)}")

    numeric_ids = [int(identifier.removeprefix("IR-")) for identifier in ledger_ids]
    if numeric_ids != sorted(numeric_ids):
        errors.append("ledger rows are not in numeric IR order")

    nonreviewed = [(row[0], row[2]) for row in ledger_rows if not row[2].lower().startswith("reviewed")]
    if nonreviewed:
        errors.append(
            "non-reviewed ledger rows: " + ", ".join(f"{identifier} ({status})" for identifier, status in nonreviewed)
        )

    body = text[graph_start:]
    heading_matches = list(SECTION_RE.finditer(body))
    section_blocks: dict[str, list[str]] = {}
    for index, match in enumerate(heading_matches):
        end = heading_matches[index + 1].start() if index + 1 < len(heading_matches) else len(body)
        section_blocks.setdefault(match.group(1), []).append(body[match.start() : end])

    duplicate_sections = sorted(identifier for identifier, blocks in section_blocks.items() if len(blocks) > 1)
    if duplicate_sections:
        errors.append(f"duplicate detailed sections: {', '.join(duplicate_sections)}")

    section_ids = set(section_blocks)
    row_ids = set(ledger_ids)
    rows_without_sections = sorted(row_ids - section_ids, key=lambda value: int(value.removeprefix("IR-")))
    sections_without_rows = sorted(section_ids - row_ids, key=lambda value: int(value.removeprefix("IR-")))
    if rows_without_sections:
        errors.append(f"ledger rows without sections: {', '.join(rows_without_sections)}")
    if sections_without_rows:
        errors.append(f"sections without ledger rows: {', '.join(sections_without_rows)}")

    wrong_decision_counts: list[tuple[str, int]] = []
    for identifier, blocks in section_blocks.items():
        count = sum(len(re.findall(r"^### Decision$", block, re.MULTILINE)) for block in blocks)
        if count != 1:
            wrong_decision_counts.append((identifier, count))
    if wrong_decision_counts:
        errors.append(
            "sections without exactly one final Decision heading: "
            + ", ".join(f"{identifier} ({count})" for identifier, count in wrong_decision_counts)
        )

    first_section = heading_matches[0].start() if heading_matches else len(body)
    graph = body[:first_section]
    stale_markers = sorted(set(match.group(0) for match in STALE_GRAPH_RE.finditer(graph)))
    if stale_markers:
        errors.append(f"stale graph closure markers: {', '.join(stale_markers)}")

    if text.count("```") % 2:
        errors.append("unbalanced fenced-code markers")

    if errors:
        print("Requirements ledger validation: FAIL", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        "Requirements ledger validation: PASS "
        f"({len(ledger_ids)} indexed rows, {len(section_ids)} detailed sections, all reviewed)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
