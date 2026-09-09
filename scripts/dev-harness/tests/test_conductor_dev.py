"""Exercise the actual Conductor adapter with controllable command boundaries."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
pytestmark = pytest.mark.skipif(os.name == "nt", reason="Conductor's local macOS shell adapter")


@pytest.mark.parametrize("event, expected", [("stop", 143), ("start-failure", 2), ("app-exit", 0)])
def test_conductor_stop_and_failed_start_drain_once(tmp_path, event, expected):
    harness = tmp_path / "scripts/dev-harness"
    harness.mkdir(parents=True)
    shutil.copyfile(REPO / "scripts/dev-harness/conductor-dev.sh", harness / "conductor-dev.sh")
    (harness / "dev-down.sh").write_text('echo down >> "$EVENTS"\n')
    (tmp_path / "Makefile").write_text(
        'dev-desktop:\n\t@test "$$OMI_DEV_APP_ROOT" = "$$HOME/Applications"\n'
        '\t@test -d "$$TMPDIR" && test "$$TMPDIR" != "$$HOME/foreign-tmp/"\n'
        '\t@echo up >> "$$EVENTS"\n'
        + ('\t@exit 23\n' if event == "start-failure" else '\t@sleep 999\n' if event == "stop" else '')
    )
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    # Deterministically deliver Conductor's stop at the foreground wait boundary;
    # no wall-clock delay, live app, emulator, network, or production signal.
    sleeper = fake_bin / "sleep"
    sleeper.write_text('#!/usr/bin/env python3\nimport os, signal\nos.killpg(os.getpgrp(), signal.SIGTERM)\n')
    sleeper.chmod(0o755)
    events = tmp_path / "events"
    result = subprocess.run(
        ["bash", str(harness / "conductor-dev.sh"), "start"],
        env={
            **os.environ,
            "HOME": str(tmp_path),
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "EVENTS": str(events),
            "TMPDIR": str(tmp_path / "foreign-tmp") + "/",
        },
        capture_output=True,
        text=True,
        timeout=10,
        start_new_session=True,
    )
    assert result.returncode == expected, result.stderr
    assert events.read_text().splitlines() == ["up", "down"]
    assert list((tmp_path / "Library/Caches/Intentive Dev Harness").iterdir()) == []


@pytest.mark.parametrize("action", ["stop", "archive"])
def test_stop_and_archive_delegate_to_existing_harness_without_removing_data(tmp_path, action):
    harness = tmp_path / "scripts/dev-harness"
    harness.mkdir(parents=True)
    shutil.copyfile(REPO / "scripts/dev-harness/conductor-dev.sh", harness / "conductor-dev.sh")
    (harness / "dev-down.sh").write_text('echo down >> "$EVENTS"\n')
    history = tmp_path / "history"
    history.write_text("keep")
    events = tmp_path / "events"
    result = subprocess.run(
        ["bash", str(harness / "conductor-dev.sh"), action],
        env={**os.environ, "EVENTS": str(events)},
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert events.read_text().splitlines() == ["down"]
    assert history.read_text() == "keep"
