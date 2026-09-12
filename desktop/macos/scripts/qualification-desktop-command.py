#!/usr/bin/env python3
"""Qualification adapter to the exact source checkout's canonical desktop owner.

Incident #107: a second launch token/signal in qualification competed with the
Dev launcher's record. Only dev_harness owns process admission and shutdown.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys


class DesktopPending(Exception):
    """The canonical launcher has not finished admitting its app yet."""


def _profile(cfg, bundle):
    from dev_harness import desktop_profile

    return desktop_profile.resolve_profile(
        cfg,
        user="alice",
        seeded_users=("alice",),
        env={"OMI_APP_NAME": bundle, "OMI_DEV_APP_ROOT": "/Applications"},
    )


def _desktop_record(cfg, bundle):
    from dev_harness import cli, safety

    safety.read_and_validate_sentinel(cfg.layout.state_root, repo_root=cfg.repo_root, instance=cfg.instance)
    path = cfg.layout.process_manifest
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        raise safety.SafetyError("Qualification process manifest is not an owner-only regular file")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise safety.SafetyError("Qualification process manifest is unreadable") from exc
    if (
        not isinstance(payload, dict)
        or payload.get("schema_version") != 1
        or not isinstance(payload.get("processes"), list)
        or any(not isinstance(record, dict) for record in payload["processes"])
    ):
        raise safety.SafetyError("Qualification process manifest is malformed")
    records = [record for record in payload["processes"] if record.get("service") == "desktop"]
    if len(records) > 1:
        raise safety.SafetyError("Qualification has multiple desktop ownership records")
    if not records:
        return None
    record = records[0]
    profile = _profile(cfg, bundle)
    expected = {
        "instance": cfg.instance,
        "state_root": str(cfg.layout.state_root),
        "app_name": profile.app_name,
        "bundle_id": profile.bundle_id,
        "app_path": str(cli.desktop_app_path(profile)),
        "executable_path": str(cli.desktop_executable_path(profile)),
        "profile_root": str(cli.desktop_profile_root(profile)),
    }
    if any(record.get(key) != value for key, value in expected.items()):
        raise safety.SafetyError("Qualification desktop belongs to a different workspace or app")
    return record


def inspect_desktop(cfg, bundle, source_sha):
    from dev_harness import cli, safety

    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise safety.SafetyError("Qualification requires an exact source SHA")
    record = _desktop_record(cfg, bundle)
    if record is None:
        raise DesktopPending("Canonical desktop launch record is missing")
    try:
        record = cli.recover_desktop_record(cfg, record)
    except cli.DesktopSuccessorPending as exc:
        raise DesktopPending("Canonical desktop successor is still starting") from exc
    if record.get("desktop_record_state") == cli.DESKTOP_RECORD_STATE_ATTEMPT:
        raise DesktopPending("Canonical desktop launch attempt is still starting")
    status, _ = cli.desktop_record_status(cfg, record)
    if status == "unhealthy":
        raise DesktopPending("Canonical desktop bridge is still starting")
    if status != "healthy":
        raise safety.SafetyError("Qualification desktop ownership is stale or unproven")
    if record.get("source_git_sha") is None:
        raise DesktopPending("Canonical launcher has not bound desktop source provenance")
    if record.get("source_git_sha") != source_sha or record.get("source_tree_dirty") is not False:
        raise safety.SafetyError("Qualification desktop source differs from the clean candidate")


def stop_desktop(cfg, bundle):
    from dev_harness import cli, safety

    if _desktop_record(cfg, bundle) is None:
        return
    cli.stop_desktop_for_relaunch(cfg, _profile(cfg, bundle))
    if _desktop_record(cfg, bundle) is not None:
        raise safety.SafetyError("Qualification desktop ownership remains after canonical shutdown")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "stop"))
    parser.add_argument("--worktree", type=Path, required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--source-sha", required=True)
    args = parser.parse_args(argv)
    # Use B's canonical owner even when this controller contains a later repair.
    sys.path.insert(0, str(args.worktree.resolve() / "scripts" / "dev-harness"))
    from dev_harness import config, safety

    try:
        cfg = config.load_config(args.worktree.resolve(), create_layout=False)
        if args.action == "inspect":
            inspect_desktop(cfg, args.bundle, args.source_sha)
        else:
            stop_desktop(cfg, args.bundle)
    except DesktopPending:
        return 3
    except (safety.SafetyError, OSError, ValueError) as exc:
        # Never print the process manifest, command line, or launch capability.
        print(f"qualification desktop {args.action} refused: {type(exc).__name__}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
