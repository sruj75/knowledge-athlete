#!/usr/bin/env python3
"""Decide whether an eligible main commit may auto-deploy the shared Dev backend."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


class AutomaticDeploymentMode(str, Enum):
    ACTIVE = "active"
    MANUAL_ONLY = "manual-only"


@dataclass(frozen=True)
class AutomaticDeploymentDecision:
    applies: bool
    reason: str


def decide(mode: str, backend_changed: bool) -> AutomaticDeploymentDecision:
    try:
        parsed_mode = AutomaticDeploymentMode(mode)
    except ValueError as exc:
        raise ValueError(f"unknown automatic backend deployment mode: {mode}") from exc
    if not backend_changed:
        return AutomaticDeploymentDecision(False, "unrelated")
    if parsed_mode is AutomaticDeploymentMode.MANUAL_ONLY:
        return AutomaticDeploymentDecision(False, "manual-required")
    return AutomaticDeploymentDecision(True, "automatic")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", required=True)
    parser.add_argument("--backend-changed", choices=("true", "false"), required=True)
    parser.add_argument("--github-output", type=Path, required=True)
    parser.add_argument("--github-step-summary", type=Path, required=True)
    args = parser.parse_args()
    decision = decide(args.mode, args.backend_changed == "true")
    with args.github_output.open("a", encoding="utf-8") as output:
        output.write(f"applies={'true' if decision.applies else 'false'}\n")
        output.write(f"reason={decision.reason}\n")
    heading = "Backend development deploy scope"
    if decision.reason == "manual-required":
        detail = "Green no-op: shared backend changes require the existing deliberate deployment workflow."
    elif decision.reason == "unrelated":
        detail = "Green no-op: the triggering commit cannot affect backend runtime or deployment inputs."
    else:
        detail = "In scope: automatic deployment is active and the triggering commit affects the backend."
    with args.github_step_summary.open("a", encoding="utf-8") as summary:
        summary.write(f"### {heading}\n{detail}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
