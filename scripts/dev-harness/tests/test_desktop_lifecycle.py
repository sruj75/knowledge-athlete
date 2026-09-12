from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dev_harness import cli, config, desktop_profile, safety

REPO_ROOT = Path(__file__).resolve().parents[3]
QUALIFICATION_DESKTOP_COMMAND_PATH = REPO_ROOT / "desktop" / "macos" / "scripts" / "qualification-desktop-command.py"


def _qualification_desktop_command():
    module_name = "qualification_desktop_command_for_lifecycle_test"
    spec = importlib.util.spec_from_file_location(module_name, QUALIFICATION_DESKTOP_COMMAND_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _qualification_inspect_argv(cfg: config.HarnessConfig, bundle: str, source_sha: str) -> list[str]:
    return [
        "inspect",
        "--worktree",
        str(cfg.repo_root),
        "--bundle",
        bundle,
        "--source-sha",
        source_sha,
    ]


def _config(monkeypatch: pytest.MonkeyPatch, tmp_path: Path, *, instance: str = "workspace-a") -> config.HarnessConfig:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_INSTANCE", instance)
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT, create_layout=True)
    monkeypatch.setattr(
        cli,
        "_process_executes_exact_path",
        lambda process, executable: process.command == str(executable) or process.command.startswith(f"{executable} "),
    )
    return cfg


def _profile(cfg: config.HarnessConfig, app_name: str = "omi-workspace-a") -> desktop_profile.DesktopLocalProfile:
    return desktop_profile.resolve_profile(
        cfg,
        user="alice",
        seeded_users=("alice",),
        env={"OMI_APP_NAME": app_name},
    )


def _snapshot(pid: int, profile: desktop_profile.DesktopLocalProfile, token: str) -> safety.ProcessSnapshot:
    command = f"{cli.desktop_executable_path(profile)} --automation-bridge --omi-launch-token={token}"
    return safety.ProcessSnapshot(
        pid=pid,
        process_start="Tue Sep  8 10:11:12 2026",
        command=command,
    )


def _record(
    cfg: config.HarnessConfig,
    profile: desktop_profile.DesktopLocalProfile,
    snapshot: safety.ProcessSnapshot,
    token: str,
) -> dict[str, object]:
    return {
        "desktop_schema_version": 1,
        "service": "desktop",
        "instance": cfg.instance,
        "pid": snapshot.pid,
        "port": cfg.automation_port,
        "owned_ports": {"automation": cfg.automation_port},
        "app_name": profile.app_name,
        "bundle_id": profile.bundle_id,
        "app_path": str(cli.desktop_app_path(profile)),
        "executable_path": str(cli.desktop_executable_path(profile)),
        "profile_root": str(cli.desktop_profile_root(profile)),
        "state_root": str(cfg.layout.state_root),
        "launch_token": token,
        "launch_transport": "open",
        "process_start": snapshot.process_start,
        "command_sha256": hashlib.sha256(snapshot.command.encode()).hexdigest(),
    }


def _write_signal(path: Path, profile: desktop_profile.DesktopLocalProfile, token: str) -> None:
    path.write_text(
        "\n".join(
            (
                "schema_version=1",
                f"bundle_id={profile.bundle_id}",
                f"app_path={cli.desktop_app_path(profile)}",
                f"executable_path={cli.desktop_executable_path(profile)}",
                f"launch_token={token}",
                "launch_transport=open",
                "",
            )
        ),
        encoding="utf-8",
    )
    path.chmod(0o600)


def test_qualification_inspection_accepts_canonical_source_bound_desktop_without_outer_token_or_signal(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    bundle = "omi-source-qualification"
    profile = _profile(cfg, bundle)
    source_sha = "a" * 40
    token = "workspaceA_launch_token_123456"
    signal_path = cfg.layout.state_root / "manifests" / "desktop-launch.signal"
    snapshot = _snapshot(40901, profile, token)
    _write_signal(signal_path, profile, token)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (snapshot,))
    monkeypatch.setattr(safety, "process_snapshot", lambda pid: snapshot if pid == snapshot.pid else None)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (snapshot.pid,) if port == cfg.automation_port else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == snapshot.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": snapshot.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
            "sourceGitSHA": source_sha,
            "sourceTreeDirty": False,
        },
    )

    registered = cli.register_desktop_launch(cfg, profile, signal_path=signal_path, launch_token=token)
    bound = cli.bind_desktop_source_provenance(cfg, registered)
    signal_path.unlink()
    monkeypatch.delenv("OMI_DESKTOP_LAUNCH_TOKEN", raising=False)

    assert bound["source_git_sha"] == source_sha
    assert qualification_desktop.inspect_desktop(cfg, bundle, source_sha) is None


def test_qualification_inspection_reports_a_missing_canonical_desktop_as_pending(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)

    with pytest.raises(qualification_desktop.DesktopPending, match="missing"):
        qualification_desktop.inspect_desktop(cfg, "omi-source-qualification", "a" * 40)


def test_qualification_command_classifies_a_missing_canonical_desktop_as_pending(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    token = "workspaceA_launch_token_must_remain_private"

    result = qualification_desktop.main(_qualification_inspect_argv(cfg, "omi-source-qualification", "a" * 40))

    captured = capsys.readouterr()
    assert result == 3
    assert token not in captured.out + captured.err
    assert "launch_token" not in captured.out + captured.err


@pytest.mark.parametrize(
    ("record_source_sha", "expected_result", "expected_stderr"),
    (
        ("a" * 40, 0, ""),
        ("b" * 40, 2, "qualification desktop inspect refused: SafetyError\n"),
    ),
    ids=("healthy", "stale-source"),
)
def test_qualification_command_classifies_source_bound_desktop_without_disclosing_its_record(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    record_source_sha: str,
    expected_result: int,
    expected_stderr: str,
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    bundle = "omi-source-qualification"
    profile = _profile(cfg, bundle)
    token = "workspaceA_launch_token_must_remain_private"
    snapshot = _snapshot(40907, profile, token)
    record = _record(cfg, profile, snapshot, token)
    record.update({"source_git_sha": record_source_sha, "source_tree_dirty": False})
    cli._save_manifests(cfg, [record])
    monkeypatch.setattr(safety, "process_snapshot", lambda pid: snapshot if pid == snapshot.pid else None)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (snapshot.pid,) if port == cfg.automation_port else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == snapshot.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": snapshot.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
            "sourceGitSHA": record_source_sha,
            "sourceTreeDirty": False,
        },
    )

    result = qualification_desktop.main(_qualification_inspect_argv(cfg, bundle, "a" * 40))

    captured = capsys.readouterr()
    emitted = captured.out + captured.err
    assert result == expected_result
    assert captured.out == ""
    assert captured.err == expected_stderr
    assert token not in emitted
    assert json.dumps(record, sort_keys=True) not in emitted
    assert "launch_token" not in emitted


def test_qualification_inspection_reports_a_canonical_launch_attempt_as_pending(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    bundle = "omi-source-qualification"
    profile = _profile(cfg, bundle)
    attempt = cli.DesktopLaunchAttempt(
        instance=cfg.instance,
        automation_port=cfg.automation_port,
        app_name=profile.app_name,
        bundle_id=profile.bundle_id,
        app_path=cli.desktop_app_path(profile),
        executable_path=cli.desktop_executable_path(profile),
        profile_root=cli.desktop_profile_root(profile),
        state_root=cfg.layout.state_root,
        launch_token="workspaceA_launch_token_123456",
        attempted_at="2026-09-08T10:11:12Z",
    ).as_record()
    cli._save_manifests(cfg, [attempt])

    with pytest.raises(qualification_desktop.DesktopPending, match="attempt"):
        qualification_desktop.inspect_desktop(cfg, bundle, "a" * 40)


def test_qualification_inspection_reports_healthy_desktop_without_bound_source_as_pending(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    bundle = "omi-source-qualification"
    profile = _profile(cfg, bundle)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(40902, profile, token)
    record = _record(cfg, profile, snapshot, token)
    cli._save_manifests(cfg, [record])
    monkeypatch.setattr(safety, "process_snapshot", lambda pid: snapshot if pid == snapshot.pid else None)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (snapshot.pid,) if port == cfg.automation_port else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == snapshot.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": snapshot.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
        },
    )

    with pytest.raises(qualification_desktop.DesktopPending, match="source"):
        qualification_desktop.inspect_desktop(cfg, bundle, "a" * 40)


def test_qualification_inspection_rejects_a_source_bound_desktop_from_another_revision(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    bundle = "omi-source-qualification"
    profile = _profile(cfg, bundle)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(40903, profile, token)
    record = _record(cfg, profile, snapshot, token)
    record.update({"source_git_sha": "b" * 40, "source_tree_dirty": False})
    cli._save_manifests(cfg, [record])
    monkeypatch.setattr(safety, "process_snapshot", lambda pid: snapshot if pid == snapshot.pid else None)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (snapshot.pid,) if port == cfg.automation_port else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == snapshot.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": snapshot.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
            "sourceGitSHA": "b" * 40,
            "sourceTreeDirty": False,
        },
    )

    with pytest.raises(safety.SafetyError, match="source"):
        qualification_desktop.inspect_desktop(cfg, bundle, "a" * 40)


def test_qualification_stop_refuses_wrong_bundle_then_stops_exact_app_and_preserves_foreign_scope(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    qualification_desktop = _qualification_desktop_command()
    cfg = _config(monkeypatch, tmp_path)
    bundle = "omi-source-qualification"
    profile = _profile(cfg, bundle)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(40904, profile, token)
    desktop_record = _record(cfg, profile, snapshot, token)
    desktop_record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    backend_record = {
        "service": "backend",
        "pid": 40905,
        "ownership_marker": cli._marker(cfg, "backend"),
        "port": cfg.backend_port,
    }
    monkeypatch.setattr(safety, "process_exists", lambda pid: pid == backend_record["pid"])
    cli._save_manifests(cfg, [backend_record, desktop_record])
    assert desktop_record["app_path"] == f"/Applications/{bundle}.app"
    current: safety.ProcessSnapshot | None = snapshot
    foreign = safety.ProcessSnapshot(40906, "Tue Sep  8 10:11:12 2026", "/usr/bin/foreign-service")
    monkeypatch.setattr(
        safety,
        "process_snapshot",
        lambda pid: current if current is not None and pid == current.pid else None,
    )
    monkeypatch.setattr(safety, "process_snapshots", lambda: (current, foreign) if current is not None else (foreign,))
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    signalled: list[tuple[int, signal.Signals]] = []

    def stop_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal current
        if current is None or pid != current.pid:
            pytest.fail("qualification cleanup must not signal another process")
        signalled.append((pid, sig))
        current = None

    monkeypatch.setattr(os, "kill", stop_exact)

    with pytest.raises(safety.SafetyError, match="different workspace or app"):
        qualification_desktop.stop_desktop(cfg, "omi-other-qualification")

    assert signalled == []
    assert cli._process_records(cfg) == [backend_record, desktop_record]
    assert qualification_desktop.stop_desktop(cfg, bundle) is None
    assert signalled == [(snapshot.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [backend_record]


@pytest.mark.parametrize("user_install", [False, True])
def test_register_desktop_launch_resolves_signal_to_one_exact_token_bound_process(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, user_install: bool
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    if user_install:
        profile = desktop_profile.resolve_profile(
            cfg,
            user="alice",
            seeded_users=("alice",),
            env={"OMI_APP_NAME": profile.app_name, "OMI_DEV_APP_ROOT": str(Path.home() / "Applications")},
        )
    token = "workspaceA_launch_token_123456"
    signal_path = cfg.layout.state_root / "manifests" / "desktop-launch.signal"
    snapshot = _snapshot(41001, profile, token)
    _write_signal(signal_path, profile, token)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (snapshot,))

    record = cli.register_desktop_launch(cfg, profile, signal_path=signal_path, launch_token=token)

    assert record["pid"] == 41001
    assert record["bundle_id"] == profile.bundle_id
    assert record["process_start"] == snapshot.process_start
    assert record["command_sha256"] == hashlib.sha256(snapshot.command.encode()).hexdigest()
    assert isinstance(cli._desktop_record_identity(cfg, record), cli.DesktopOwnershipRecord)
    assert cli._process_records(cfg)[-1] == record


def test_registration_timeout_retains_owner_only_typed_launch_attempt(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    fake_run = tmp_path / "run.sh"
    fake_run.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    fake_run.chmod(0o755)
    monkeypatch.setattr(cli, "_require_port_available_or_owned", lambda *_args, **_kwargs: None)

    with pytest.raises(safety.SafetyError, match="launch signal is missing"):
        cli.launch_desktop_local(
            cfg,
            profile,
            run_sh=fake_run,
            wait_for_exit=False,
            registration_timeout=0,
        )

    records = cli._process_records(cfg)
    assert len(records) == 1
    attempt = cli._desktop_launch_attempt(cfg, records[0])
    assert attempt.executable_path == cli.desktop_executable_path(profile)
    assert attempt.automation_port == cfg.automation_port
    assert cfg.layout.process_manifest.stat().st_mode & 0o777 == 0o600


def test_compile_failure_without_launch_signal_clears_attempt_for_an_ordinary_retry(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    fake_run = tmp_path / "run.sh"
    fake_run.write_text("#!/bin/sh\nexit 23\n", encoding="utf-8")
    fake_run.chmod(0o755)
    monkeypatch.setattr(cli, "_require_port_available_or_owned", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: ())

    with pytest.raises(subprocess.CalledProcessError):
        cli.launch_desktop_local(cfg, profile, run_sh=fake_run, wait_for_exit=False)

    assert cli._process_records(cfg) == []
    cli.stop_desktop_for_relaunch(cfg, profile, wait_seconds=0)


def test_nonzero_launcher_after_handoff_marker_retains_attempt_for_delayed_process(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    fake_run = tmp_path / "run.sh"
    fake_run.write_text(
        "#!/bin/sh\nprintf 'launch_transport=pending\\n' > \"$OMI_DESKTOP_LAUNCH_SIGNAL_FILE\"\n"
        "chmod 600 \"$OMI_DESKTOP_LAUNCH_SIGNAL_FILE\"\nexit 23\n",
        encoding="utf-8",
    )
    fake_run.chmod(0o755)
    monkeypatch.setattr(cli, "_require_port_available_or_owned", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: ())

    with pytest.raises(subprocess.CalledProcessError):
        cli.launch_desktop_local(cfg, profile, run_sh=fake_run, wait_for_exit=False)

    records = cli._process_records(cfg)
    assert len(records) == 1
    assert isinstance(cli._desktop_launch_attempt(cfg, records[0]), cli.DesktopLaunchAttempt)
    with pytest.raises(safety.SafetyError, match="launch attempt is unresolved"):
        cli.stop_desktop_for_relaunch(cfg, profile, wait_seconds=0)


def test_delayed_token_bound_launch_is_recovered_from_attempt_and_stopped_exactly(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    attempt = cli.DesktopLaunchAttempt(
        instance=cfg.instance,
        automation_port=cfg.automation_port,
        app_name=profile.app_name,
        bundle_id=profile.bundle_id,
        app_path=cli.desktop_app_path(profile),
        executable_path=cli.desktop_executable_path(profile),
        profile_root=cli.desktop_profile_root(profile),
        state_root=cfg.layout.state_root,
        launch_token=token,
        attempted_at="2026-09-08T10:11:12Z",
    ).as_record()
    cli._save_manifests(cfg, [attempt])
    current: safety.ProcessSnapshot | None = _snapshot(41501, profile, token)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (current,) if current is not None else ())
    monkeypatch.setattr(
        safety, "process_snapshot", lambda pid: current if current is not None and pid == current.pid else None
    )
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    signalled: list[tuple[int, signal.Signals]] = []

    def stop_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal current
        assert current is not None and pid == current.pid
        signalled.append((pid, sig))
        current = None

    monkeypatch.setattr(os, "kill", stop_exact)

    assert cli.stop_desktop_record(cfg, attempt, wait_seconds=0) is True
    assert signalled == [(41501, signal.SIGTERM)]


def test_tokenless_permission_reopen_adopts_only_one_exact_health_and_source_bound_successor(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(41601, profile, token)
    record = _record(cfg, profile, predecessor, token)
    record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    successor = safety.ProcessSnapshot(
        pid=41602,
        process_start="Tue Sep  8 10:12:12 2026",
        command=str(cli.desktop_executable_path(profile)),
    )
    foreign = tuple(
        safety.ProcessSnapshot(42000 + index, "Tue Sep  8 10:12:12 2026", f"/usr/bin/foreign-{index}")
        for index in range(200)
    )
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (*foreign, successor))
    exact_probes: list[int] = []

    def exact_executable(process: safety.ProcessSnapshot, executable: Path) -> bool:
        exact_probes.append(process.pid)
        return process.pid == successor.pid and executable == cli.desktop_executable_path(profile)

    monkeypatch.setattr(cli, "_process_executes_exact_path", exact_executable)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (successor.pid,) if port == cfg.automation_port else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == successor.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": successor.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": f"{cfg.backend_url}/",
            "sourceGitSHA": "a" * 40,
            "sourceTreeDirty": False,
        },
    )

    recovered = cli.recover_desktop_record(cfg, record)

    assert recovered["pid"] == successor.pid
    assert recovered["desktop_ownership_proof"] == "bridge_successor"
    assert recovered["predecessor_pid"] == predecessor.pid
    assert exact_probes == [successor.pid]
    assert cli._process_records(cfg)[-1] == recovered


def test_tokenless_successor_with_different_source_is_not_adopted_or_signalled(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(41701, profile, token)
    record = _record(cfg, profile, predecessor, token)
    record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    successor = safety.ProcessSnapshot(41702, "Tue Sep  8 10:12:12 2026", str(cli.desktop_executable_path(profile)))
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (successor,))
    monkeypatch.setattr(safety, "listening_pids", lambda _port: (successor.pid,))
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == successor.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": successor.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
            "sourceGitSHA": "b" * 40,
            "sourceTreeDirty": False,
        },
    )
    monkeypatch.setattr(os, "kill", lambda *_args: pytest.fail("mismatched successor must not be signalled"))

    with pytest.raises(safety.SafetyError, match="source provenance differs"):
        cli.recover_desktop_record(cfg, record)

    assert cli._process_records(cfg) == []


def test_successor_recovery_rejects_two_exact_executables_before_health_or_signal(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(41801, profile, token)
    record = _record(cfg, profile, predecessor, token)
    record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    successors = tuple(
        safety.ProcessSnapshot(
            41802 + index,
            "Tue Sep  8 10:12:12 2026",
            str(cli.desktop_executable_path(profile)),
        )
        for index in range(2)
    )
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: successors)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: pytest.fail("ambiguous candidates must not reach health admission"),
    )
    monkeypatch.setattr(os, "kill", lambda *_args: pytest.fail("ambiguous candidates must not be signalled"))

    with pytest.raises(safety.SafetyError, match="successor ownership is ambiguous"):
        cli.recover_desktop_record(cfg, record)


def test_relaunch_preserves_predecessor_when_exact_successor_bridge_is_still_starting(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(41901, profile, token)
    record = _record(cfg, profile, predecessor, token)
    record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    successor = safety.ProcessSnapshot(
        41902,
        "Tue Sep  8 10:12:12 2026",
        str(cli.desktop_executable_path(profile)),
    )
    cli._save_manifests(cfg, [record])
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (successor,))
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    monkeypatch.setattr(os, "kill", lambda *_args: pytest.fail("unverified successor must not be signalled"))

    with pytest.raises(cli.DesktopSuccessorPending, match="bridge identity is not ready"):
        cli.stop_desktop_for_relaunch(cfg, profile, wait_seconds=0)

    assert cli._process_records(cfg) == [record]


def test_register_rejects_a_foreign_automation_listener_without_adopting_or_signalling_it(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    signal_path = cfg.layout.state_root / "manifests" / "desktop-launch.signal"
    _write_signal(signal_path, profile, token)
    foreign = safety.ProcessSnapshot(pid=42002, process_start="other", command="/usr/bin/python foreign")
    monkeypatch.setattr(safety, "process_snapshots", lambda: (foreign,))
    monkeypatch.setattr(safety, "listening_pids", lambda _port: (foreign.pid,))
    monkeypatch.setattr(os, "kill", lambda _pid, _sig: pytest.fail("foreign listener must not be signalled"))

    with pytest.raises(safety.SafetyError, match="matching processes=0"):
        cli.register_desktop_launch(cfg, profile, signal_path=signal_path, launch_token=token)

    assert not any(record.get("service") == "desktop" for record in cli._process_records(cfg))


def test_desktop_status_rejects_pid_reuse_and_stop_sends_no_signal(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    recorded = _snapshot(43003, profile, token)
    record = _record(cfg, profile, recorded, token)
    reused = safety.ProcessSnapshot(
        pid=recorded.pid,
        process_start="Tue Sep  8 11:12:13 2026",
        command="/System/Library/CoreServices/unrelated-xpc",
    )
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: reused)
    monkeypatch.setattr(os, "kill", lambda _pid, _sig: pytest.fail("reused PID must not be signalled"))

    status, detail = cli.desktop_record_status(cfg, record)

    assert status == "stale/unowned"
    assert "launch provenance" in detail
    with pytest.raises(safety.SafetyError, match="launch provenance"):
        cli.stop_desktop_record(cfg, record, wait_seconds=0)


def test_legacy_unowned_desktop_record_is_never_signalled(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    cfg = _config(monkeypatch, tmp_path)
    legacy = {
        "service": "desktop",
        "pid": 44004,
        "bundle_id": "com.heyintentive.intentive.dev.omi-old",
        "port": cfg.automation_port,
    }
    monkeypatch.setattr(
        safety,
        "process_snapshot",
        lambda _pid: safety.ProcessSnapshot(44004, "old", "/Applications/omi-old.app/Contents/MacOS/Omi Computer"),
    )
    monkeypatch.setattr(os, "kill", lambda _pid, _sig: pytest.fail("legacy record must not be signalled"))

    status, detail = cli.desktop_record_status(cfg, legacy)

    assert status == "stale/unowned"
    assert "typed provenance" in detail
    with pytest.raises(safety.SafetyError, match="typed provenance"):
        cli.stop_desktop_record(cfg, legacy, wait_seconds=0)


@pytest.mark.parametrize("user_install", [False, True])
def test_relaunch_stops_only_workspace_a_desktop_and_preserves_backend_and_workspace_b(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, user_install: bool
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    if user_install:
        profile = desktop_profile.resolve_profile(
            cfg,
            user="alice",
            seeded_users=("alice",),
            env={"OMI_APP_NAME": profile.app_name, "OMI_DEV_APP_ROOT": str(Path.home() / "Applications")},
        )
    token = "workspaceA_launch_token_123456"
    desktop = _snapshot(45005, profile, token)
    desktop_record = _record(cfg, profile, desktop, token)
    # Existing system-installed owners remain stoppable after a user opts into
    # the standard-account destination. Shutdown follows the recorded owner.
    monkeypatch.setenv("OMI_DEV_APP_ROOT", str(Path.home() / "Applications"))
    backend_record = {
        "service": "backend",
        "pid": 45006,
        "ownership_marker": cli._marker(cfg, "backend"),
        "port": cfg.backend_port,
    }
    cli._write_json(cfg.layout.process_manifest, {"processes": [backend_record, desktop_record]})
    preserved_apps = {"workspace-b": 45007, "Omi Beta": 45008, "Omi": 45009}
    desktop_running = True
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: desktop if desktop_running else None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (desktop,) if desktop_running else ())
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    signalled: list[tuple[int, signal.Signals]] = []

    def stop_desktop(pid: int, sig: signal.Signals) -> None:
        nonlocal desktop_running
        signalled.append((pid, sig))
        desktop_running = False

    monkeypatch.setattr(os, "kill", stop_desktop)
    monkeypatch.setattr(
        safety,
        "process_exists",
        lambda pid: pid == backend_record["pid"] or pid in preserved_apps.values(),
    )

    cli.stop_desktop_for_relaunch(cfg, profile, wait_seconds=0)

    assert signalled == [(desktop.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [backend_record]
    assert not any(pid in preserved_apps.values() for pid, _sig in signalled)


def test_start_twice_replaces_only_the_desktop_and_preserves_owned_services(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    services = [
        {
            "service": "firestore",
            "pid": 45101,
            "process_group": 45101,
            "port": cfg.firestore_port,
            "owned_ports": {"firestore": cfg.firestore_port, "auth": cfg.auth_port},
            "ownership_marker": cli._marker(cfg, "firestore"),
        },
        {
            "service": "redis",
            "pid": 45102,
            "process_group": 45102,
            "port": cfg.redis_port,
            "owned_ports": {"redis": cfg.redis_port},
            "ownership_marker": cli._marker(cfg, "redis"),
        },
        {
            "service": "backend",
            "pid": 45103,
            "process_group": 45103,
            "port": cfg.backend_port,
            "owned_ports": {"backend": cfg.backend_port},
            "ownership_marker": cli._marker(cfg, "backend"),
        },
    ]
    cli._write_json(cfg.layout.process_manifest, {"processes": services})
    service_pids = {int(record["pid"]) for record in services}
    current: safety.ProcessSnapshot | None = None
    launches = 0
    signalled: list[tuple[int, signal.Signals]] = []

    def fake_run(
        _command: list[str], *, cwd: Path, env: dict[str, str], check: bool
    ) -> subprocess.CompletedProcess[str]:
        nonlocal current, launches
        assert cwd == cfg.repo_root / "desktop" / "macos"
        assert check is True
        launches += 1
        token = env["OMI_DESKTOP_LAUNCH_TOKEN"]
        current = safety.ProcessSnapshot(
            45200 + launches,
            f"Tue Sep 8 10:11:1{launches} 2026",
            f"{cli.desktop_executable_path(profile)} --automation-bridge --omi-launch-token={token}",
        )
        _write_signal(Path(env["OMI_DESKTOP_LAUNCH_SIGNAL_FILE"]), profile, token)
        return subprocess.CompletedProcess(_command, 0)

    def process_snapshot(pid: int) -> safety.ProcessSnapshot | None:
        return current if current is not None and current.pid == pid else None

    def stop_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal current
        if current is None or pid != current.pid:
            pytest.fail(f"non-desktop PID {pid} must not be signalled")
        signalled.append((pid, sig))
        current = None

    def bridge_payload(_port: int) -> dict[str, object]:
        assert current is not None
        return {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": current.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
        }

    monkeypatch.setattr(cli.subprocess, "run", fake_run)
    monkeypatch.setattr(cli, "_require_port_available_or_owned", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (current,) if current is not None else ())
    monkeypatch.setattr(safety, "process_snapshot", process_snapshot)
    monkeypatch.setattr(safety, "process_exists", lambda pid: pid in service_pids)
    monkeypatch.setattr(
        safety,
        "listening_pids",
        lambda port: (current.pid,) if port == cfg.automation_port and current is not None else (),
    )
    monkeypatch.setattr(cli, "_desktop_bridge_payload", bridge_payload)
    monkeypatch.setattr(os, "kill", stop_exact)
    run_sh = cfg.repo_root / "desktop" / "macos" / "run.sh"

    first = cli.launch_desktop_local(cfg, profile, run_sh=run_sh, wait_for_exit=False)
    second = cli.launch_desktop_local(cfg, profile, run_sh=run_sh, wait_for_exit=False)

    assert first["pid"] == 45201
    assert second["pid"] == 45202
    assert signalled == [(45201, signal.SIGTERM)]
    records = cli._process_records(cfg)
    assert [record for record in records if record.get("service") != "desktop"] == services
    assert [record["pid"] for record in records if record.get("service") == "desktop"] == [45202]


@pytest.mark.parametrize("backend_suffix", ["", "/"])
def test_desktop_status_binds_exact_process_listener_and_bridge_identity(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, backend_suffix: str
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(46006, profile, token)
    record = _record(cfg, profile, snapshot, token)
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: snapshot)
    monkeypatch.setattr(safety, "listening_pids", lambda _port: (snapshot.pid,))
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": snapshot.pid,
            "bridgePort": cfg.automation_port,
            # Real app health normalizes its root URL with a trailing slash.
            "backendURL": cfg.backend_url + backend_suffix,
        },
    )

    assert cli.desktop_record_status(cfg, record) == ("healthy", "exact process and bridge")


def test_desktop_status_rejects_a_bridge_owned_by_another_named_bundle(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(47007, profile, token)
    record = _record(cfg, profile, snapshot, token)
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: snapshot)
    monkeypatch.setattr(safety, "listening_pids", lambda _port: (snapshot.pid,))
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": "com.heyintentive.intentive.dev.omi-workspace-b",
            "processID": 48008,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
        },
    )

    status, detail = cli.desktop_record_status(cfg, record)

    assert status == "stale/unowned"
    assert "bridge identity" in detail


def test_desktop_stop_fails_closed_when_exact_process_survives_term_and_kill(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(48008, profile, token)
    record = _record(cfg, profile, snapshot, token)
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: snapshot)
    signalled: list[tuple[int, signal.Signals]] = []
    monkeypatch.setattr(os, "kill", lambda pid, sig: signalled.append((pid, sig)))

    with pytest.raises(safety.SafetyError, match="still running"):
        cli.stop_desktop_record(cfg, record, wait_seconds=0, kill_wait_seconds=0)

    assert signalled == [(snapshot.pid, signal.SIGTERM), (snapshot.pid, signal.SIGKILL)]


def test_desktop_stop_keeps_authorized_identity_when_executable_proof_disappears_during_shutdown(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(48508, profile, token)
    record = _record(cfg, profile, snapshot, token)
    current: safety.ProcessSnapshot | None = snapshot
    shutdown_started = False
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: current)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (current,) if current is not None else ())
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())

    def exact_executable(_process: safety.ProcessSnapshot, _executable: Path) -> bool:
        if shutdown_started:
            pytest.fail("post-signal shutdown must not require a live executable mapping")
        return True

    monkeypatch.setattr(cli, "_process_executes_exact_path", exact_executable)
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal shutdown_started
        assert pid == snapshot.pid
        shutdown_started = True
        signalled.append((pid, sig))

    def finish_shutdown(_seconds: float) -> None:
        nonlocal current
        current = None

    monkeypatch.setattr(os, "kill", signal_exact)
    monkeypatch.setattr(cli.time, "sleep", finish_shutdown)

    assert cli.stop_desktop_record(cfg, record, wait_seconds=1) is True
    assert signalled == [(snapshot.pid, signal.SIGTERM)]


def test_desktop_stop_tolerates_command_rendering_change_for_same_started_process_until_exit(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(48517, profile, token)
    draining = safety.ProcessSnapshot(snapshot.pid, snapshot.process_start, "(Omi Computer)")
    record = _record(cfg, profile, snapshot, token)
    current: safety.ProcessSnapshot | None = snapshot
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: current)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (current,) if current is not None else ())
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal current
        assert pid == snapshot.pid
        current = draining
        signalled.append((pid, sig))

    def finish_shutdown(_seconds: float) -> None:
        nonlocal current
        current = None

    monkeypatch.setattr(os, "kill", signal_exact)
    monkeypatch.setattr(cli.time, "sleep", finish_shutdown)

    assert cli.stop_desktop_record(cfg, record, wait_seconds=1) is True
    assert signalled == [(snapshot.pid, signal.SIGTERM)]


def test_desktop_stop_rejects_changed_process_start_during_passive_drain_without_escalation(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(48516, profile, token)
    reused = safety.ProcessSnapshot(snapshot.pid, "Tue Sep  8 10:13:12 2026", "(unrelated)")
    record = _record(cfg, profile, snapshot, token)
    cli._save_manifests(cfg, [record])
    current = snapshot
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: current)
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal current
        assert pid == snapshot.pid
        current = reused
        signalled.append((pid, sig))

    monkeypatch.setattr(os, "kill", signal_exact)

    assert cli._stop_owned(cfg) is False
    assert signalled == [(snapshot.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [record]


def test_desktop_stop_preserves_a_pending_successor_that_appears_during_term_drain(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(48510, profile, token)
    record = _record(cfg, profile, predecessor, token)
    record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    successor = safety.ProcessSnapshot(
        pid=48511,
        process_start="Tue Sep  8 10:12:12 2026",
        command=str(cli.desktop_executable_path(profile)),
    )
    cli._save_manifests(cfg, [record])
    term_sent = False
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None if term_sent else predecessor)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (successor,) if term_sent else (predecessor,))
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_predecessor(pid: int, sig: signal.Signals) -> None:
        nonlocal term_sent
        assert pid == predecessor.pid
        term_sent = True
        signalled.append((pid, sig))

    monkeypatch.setattr(os, "kill", signal_predecessor)

    with pytest.raises(cli.DesktopSuccessorPending, match="bridge identity is not ready"):
        cli.stop_desktop_for_relaunch(cfg, profile)

    assert signalled == [(predecessor.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [record]


def test_desktop_stop_preserves_evidence_when_a_foreign_listener_remains_after_term(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(48512, profile, token)
    record = _record(cfg, profile, predecessor, token)
    foreign_pid = 48513
    cli._save_manifests(cfg, [record])
    term_sent = False
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None if term_sent else predecessor)
    monkeypatch.setattr(safety, "process_snapshots", lambda: () if term_sent else (predecessor,))
    monkeypatch.setattr(
        safety,
        "listening_pids",
        lambda port: (foreign_pid,) if term_sent and port == cfg.automation_port else (),
    )
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_predecessor(pid: int, sig: signal.Signals) -> None:
        nonlocal term_sent
        if pid != predecessor.pid:
            pytest.fail("an unowned listener must not be signalled")
        term_sent = True
        signalled.append((pid, sig))

    monkeypatch.setattr(os, "kill", signal_predecessor)

    with pytest.raises(safety.SafetyError, match="shutdown is incomplete"):
        cli.stop_desktop_for_relaunch(cfg, profile)

    assert signalled == [(predecessor.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [record]


def test_relaunch_preserves_an_admitted_successor_that_appears_during_term_drain(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    predecessor = _snapshot(48514, profile, token)
    record = _record(cfg, profile, predecessor, token)
    record.update({"source_git_sha": "a" * 40, "source_tree_dirty": False})
    successor = safety.ProcessSnapshot(
        pid=48515,
        process_start="Tue Sep  8 10:12:12 2026",
        command=str(cli.desktop_executable_path(profile)),
    )
    cli._save_manifests(cfg, [record])
    term_sent = False
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None if term_sent else predecessor)
    monkeypatch.setattr(safety, "process_snapshots", lambda: (successor,) if term_sent else (predecessor,))
    monkeypatch.setattr(safety, "listening_pids", lambda _port: (successor.pid,) if term_sent else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda pid, ancestor: pid == ancestor == successor.pid)
    monkeypatch.setattr(
        cli,
        "_desktop_bridge_payload",
        lambda _port: {
            "ok": True,
            "bundleIdentifier": profile.bundle_id,
            "processID": successor.pid,
            "bridgePort": cfg.automation_port,
            "backendURL": cfg.backend_url,
            "sourceGitSHA": "a" * 40,
            "sourceTreeDirty": False,
        },
    )
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_predecessor(pid: int, sig: signal.Signals) -> None:
        nonlocal term_sent
        if pid != predecessor.pid:
            pytest.fail("the recovered successor must be retained for an exact retry")
        term_sent = True
        signalled.append((pid, sig))

    monkeypatch.setattr(os, "kill", signal_predecessor)

    with pytest.raises(safety.SafetyError, match="shutdown is incomplete"):
        cli.stop_desktop_for_relaunch(cfg, profile)

    recovered = cli._process_records(cfg)
    assert signalled == [(predecessor.pid, signal.SIGTERM)]
    assert len(recovered) == 1
    assert recovered[0]["pid"] == successor.pid
    assert recovered[0]["desktop_ownership_proof"] == "bridge_successor"


def test_desktop_stop_requires_full_command_proof_again_before_kill_escalation(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(48509, profile, token)
    draining = safety.ProcessSnapshot(snapshot.pid, snapshot.process_start, "(Omi Computer)")
    record = _record(cfg, profile, snapshot, token)
    cli._save_manifests(cfg, [record])
    current = snapshot
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: current)
    times = iter((0.0, 9.0))
    monkeypatch.setattr(cli.time, "time", lambda: next(times))
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal current
        assert pid == snapshot.pid
        signalled.append((pid, sig))
        current = draining

    monkeypatch.setattr(os, "kill", signal_exact)

    assert cli._stop_owned(cfg) is False

    assert signalled == [(snapshot.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [record]


def test_desktop_stop_requires_exact_executable_again_before_kill_escalation(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    snapshot = _snapshot(48518, profile, token)
    record = _record(cfg, profile, snapshot, token)
    cli._save_manifests(cfg, [record])
    exact_executable = True
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: snapshot)
    monkeypatch.setattr(cli, "_process_executes_exact_path", lambda *_args: exact_executable)
    times = iter((0.0, 9.0))
    monkeypatch.setattr(cli.time, "time", lambda: next(times))
    signalled: list[tuple[int, signal.Signals]] = []

    def signal_exact(pid: int, sig: signal.Signals) -> None:
        nonlocal exact_executable
        assert pid == snapshot.pid
        signalled.append((pid, sig))
        exact_executable = False

    monkeypatch.setattr(os, "kill", signal_exact)

    assert cli._stop_owned(cfg) is False
    assert signalled == [(snapshot.pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == [record]


def test_dev_down_retry_clears_a_settled_desktop_record_after_process_and_listener_exit(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    token = "workspaceA_launch_token_123456"
    record = _record(cfg, profile, _snapshot(48608, profile, token), token)
    cli._save_manifests(cfg, [record])
    monkeypatch.setattr(cli, "_repo_root", lambda: REPO_ROOT)
    monkeypatch.setattr(config, "load_config", lambda *_args, **_kwargs: cfg)
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: None)
    monkeypatch.setattr(safety, "process_snapshots", lambda: ())
    monkeypatch.setattr(safety, "listening_pids", lambda _port: ())
    monkeypatch.setattr(os, "kill", lambda *_args: pytest.fail("an exited desktop must not be signalled"))

    assert cli.cmd_down(argparse.Namespace()) == 0
    assert cli._process_records(cfg) == []


def test_local_launcher_runs_fake_run_sh_with_scrubbed_app_environment(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    fake_run = tmp_path / "run.sh"
    captured_env = tmp_path / "captured-env"
    fake_run.write_text(f"#!/bin/sh\nenv > {captured_env}\n", encoding="utf-8")
    fake_run.chmod(0o755)
    monkeypatch.setenv("OPENAI_API_KEY", "provider-secret")
    monkeypatch.setenv("LANGFUSE_SECRET_KEY", "observability-secret")
    monkeypatch.setenv("ADMIN_KEY", "backend-admin-secret")
    monkeypatch.setenv("OMI_ADMIN_TOKEN", "ambient-admin-secret")
    monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", "/tmp/service-account.json")
    monkeypatch.setenv("OMI_LLM_STUB", "1")
    monkeypatch.setenv("OMI_HARNESS_OWNERSHIP_TOKEN", "backend-process-capability")
    monkeypatch.setattr(cli, "stop_desktop_for_relaunch", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(cli, "_require_port_available_or_owned", lambda *_args, **_kwargs: None)
    record = {"service": "desktop", "pid": 49009}
    monkeypatch.setattr(cli, "register_desktop_launch", lambda *_args, **_kwargs: record)
    monkeypatch.setattr(cli, "desktop_record_status", lambda *_args, **_kwargs: ("healthy", "exact process and bridge"))
    monkeypatch.setattr(cli, "bind_desktop_source_provenance", lambda _cfg, desktop: desktop)

    launched = cli.launch_desktop_local(
        cfg,
        profile,
        run_sh=fake_run,
        wait_for_exit=False,
        registration_timeout=0,
        health_timeout=0,
    )

    assert launched == record
    captured = dict(line.split("=", 1) for line in captured_env.read_text(encoding="utf-8").splitlines())
    assert captured["OMI_PYTHON_API_URL"] == cfg.backend_url
    assert captured["FIREBASE_AUTH_EMULATOR_HOST"] == cfg.auth_host
    assert captured["OMI_AUTOMATION_PORT"] == str(cfg.automation_port)
    assert captured["OMI_DESKTOP_LAUNCH_SIGNAL_FILE"].startswith(str(cfg.layout.state_root))
    assert len(captured["OMI_DESKTOP_LAUNCH_TOKEN"]) >= 16
    for key in (
        "OPENAI_API_KEY",
        "LANGFUSE_SECRET_KEY",
        "ADMIN_KEY",
        "OMI_ADMIN_TOKEN",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "PROVIDER_MODE",
        "OMI_ENV_STAGE",
        "OMI_LLM_STUB",
        "OMI_HARNESS_OWNERSHIP_TOKEN",
    ):
        assert key not in captured


def test_failed_launch_cleanup_preserves_record_when_process_identity_is_no_longer_proven(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    profile = _profile(cfg)
    fake_run = tmp_path / "run.sh"
    fake_run.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    fake_run.chmod(0o755)
    record = {"service": "desktop", "pid": 49509, "diagnostic": "preserve-me"}
    monkeypatch.setattr(cli, "stop_desktop_for_relaunch", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(cli, "_require_port_available_or_owned", lambda *_args, **_kwargs: None)

    def register(*_args: object, **_kwargs: object) -> dict[str, object]:
        cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
        return record

    monkeypatch.setattr(cli, "register_desktop_launch", register)
    monkeypatch.setattr(cli, "desktop_record_status", lambda *_args, **_kwargs: ("stale/unowned", "PID reused"))
    monkeypatch.setattr(
        cli,
        "stop_desktop_record",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(safety.SafetyError("launch provenance changed")),
    )

    with pytest.raises(safety.SafetyError, match="launch provenance changed"):
        cli.launch_desktop_local(
            cfg,
            profile,
            run_sh=fake_run,
            wait_for_exit=False,
            registration_timeout=0,
            health_timeout=0,
        )

    assert cli._process_records(cfg) == [record]


def test_dev_down_routes_desktop_through_exact_pid_stop_not_process_group(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    record = {"service": "desktop", "pid": 50010}
    cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
    exact_stops: list[int] = []
    monkeypatch.setattr(
        cli,
        "stop_desktop_record",
        lambda _cfg, desktop, **_kwargs: exact_stops.append(int(desktop["pid"])) or True,
    )
    monkeypatch.setattr(
        cli,
        "_signal_owned_supervisor",
        lambda _pid, _service: pytest.fail("desktop must not be process-group signalled"),
    )
    monkeypatch.setattr(safety, "process_exists", lambda _pid: False)

    cli._stop_owned(cfg)

    assert exact_stops == [50010]
    assert cli._process_records(cfg) == []


def test_dev_down_captures_and_stops_an_owned_listener_that_reparents_after_supervisor_exit(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    supervisor_pid, listener_pid = 51011, 51012
    record = {
        "service": "firestore",
        "pid": supervisor_pid,
        "process_group": supervisor_pid,
        "port": cfg.firestore_port,
        "owned_ports": {"firestore": cfg.firestore_port},
        "ownership_marker": cli._marker(cfg, "firestore"),
    }
    cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
    cli._write_json(
        cfg.layout.port_manifest,
        {"ports": [{"service": "firestore", "port": cfg.firestore_port, "pid": supervisor_pid}]},
    )
    supervisor_alive = True
    listener_alive = True
    listener = safety.ProcessSnapshot(listener_pid, "Tue Sep  8 15:41:59 2026", "/usr/bin/java firestore-emulator")

    monkeypatch.setattr(cli, "SERVICE_STOP_PHASES", ((signal.SIGINT, 0), (signal.SIGTERM, 0)))
    monkeypatch.setattr(
        safety, "process_exists", lambda pid: supervisor_alive if pid == supervisor_pid else listener_alive
    )
    monkeypatch.setattr(safety, "validate_owned_pid", lambda *_args, **_kwargs: record)
    monkeypatch.setattr(
        safety,
        "listening_pids",
        lambda port: (listener_pid,) if port == cfg.firestore_port and listener_alive else (),
    )
    monkeypatch.setattr(
        safety, "is_descendant_of", lambda child, parent: child == listener_pid and parent == supervisor_pid
    )
    monkeypatch.setattr(
        safety, "process_snapshot", lambda pid: listener if pid == listener_pid and listener_alive else None
    )

    group_signals: list[tuple[int, signal.Signals]] = []
    listener_signals: list[tuple[int, signal.Signals]] = []

    def signal_group(pid: int, service: str, sig: signal.Signals = signal.SIGINT) -> None:
        nonlocal supervisor_alive
        assert (pid, service) == (supervisor_pid, "firestore")
        group_signals.append((pid, sig))
        supervisor_alive = False

    def signal_listener(pid: int, sig: signal.Signals) -> None:
        nonlocal listener_alive
        listener_signals.append((pid, sig))
        listener_alive = False

    monkeypatch.setattr(cli, "_signal_owned_supervisor", signal_group)
    monkeypatch.setattr(os, "kill", signal_listener)

    cli._stop_owned(cfg)

    assert group_signals == [(supervisor_pid, signal.SIGINT)]
    assert listener_signals == [(listener_pid, signal.SIGTERM)]
    assert cli._process_records(cfg) == []


def test_dev_down_preserves_listener_evidence_when_recorded_child_pid_is_reused(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    supervisor_pid, listener_pid = 52021, 52022
    record = {
        "service": "firestore",
        "pid": supervisor_pid,
        "process_group": supervisor_pid,
        "port": cfg.firestore_port,
        "owned_ports": {"firestore": cfg.firestore_port},
        "ownership_marker": cli._marker(cfg, "firestore"),
    }
    cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
    cli._write_json(
        cfg.layout.port_manifest,
        {"ports": [{"service": "firestore", "port": cfg.firestore_port, "pid": supervisor_pid}]},
    )
    supervisor_alive = True
    captured = safety.ProcessSnapshot(listener_pid, "Tue Sep  8 15:41:59 2026", "/usr/bin/java firestore-emulator")
    reused = safety.ProcessSnapshot(listener_pid, "Tue Sep  8 16:00:00 2026", "/usr/bin/python foreign")
    snapshots = iter((captured, reused, reused))
    monkeypatch.setattr(cli, "SERVICE_STOP_PHASES", ((signal.SIGINT, 0), (signal.SIGTERM, 0)))
    monkeypatch.setattr(safety, "process_exists", lambda pid: supervisor_alive if pid == supervisor_pid else True)
    monkeypatch.setattr(safety, "validate_owned_pid", lambda *_args, **_kwargs: record)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (listener_pid,) if port == cfg.firestore_port else ())
    monkeypatch.setattr(
        safety, "is_descendant_of", lambda child, parent: child == listener_pid and parent == supervisor_pid
    )
    monkeypatch.setattr(safety, "process_snapshot", lambda _pid: next(snapshots))

    def signal_group(_pid: int, _service: str, _sig: signal.Signals = signal.SIGINT) -> None:
        nonlocal supervisor_alive
        supervisor_alive = False

    monkeypatch.setattr(cli, "_signal_owned_supervisor", signal_group)
    monkeypatch.setattr(os, "kill", lambda _pid, _sig: pytest.fail("reused child PID must not be signalled"))

    stopped = cli._stop_owned(cfg)

    assert stopped is False
    retained = cli._process_records(cfg)
    assert len(retained) == 1
    assert retained[0]["service"] == "firestore"
    assert retained[0]["listener_processes"][0]["pid"] == listener_pid


def test_dev_down_does_not_signal_a_foreign_listener_on_an_owned_port(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    supervisor_pid, foreign_pid = 53031, 53032
    record = {
        "service": "firestore",
        "pid": supervisor_pid,
        "process_group": supervisor_pid,
        "port": cfg.firestore_port,
        "owned_ports": {"firestore": cfg.firestore_port},
        "ownership_marker": cli._marker(cfg, "firestore"),
    }
    cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
    cli._write_json(
        cfg.layout.port_manifest,
        {"ports": [{"service": "firestore", "port": cfg.firestore_port, "pid": supervisor_pid}]},
    )
    monkeypatch.setattr(safety, "process_exists", lambda pid: pid == supervisor_pid)
    monkeypatch.setattr(safety, "validate_owned_pid", lambda *_args, **_kwargs: record)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (foreign_pid,) if port == cfg.firestore_port else ())
    monkeypatch.setattr(safety, "is_descendant_of", lambda _child, _parent: False)
    monkeypatch.setattr(
        cli,
        "_signal_owned_supervisor",
        lambda _pid, _service, _sig=signal.SIGINT: pytest.fail("foreign listener blocks the group signal"),
    )
    monkeypatch.setattr(os, "kill", lambda _pid, _sig: pytest.fail("foreign listener must not be signalled"))

    stopped = cli._stop_owned(cfg)

    assert stopped is False
    assert cli._process_records(cfg)[0]["service"] == "firestore"


def test_dev_down_preserves_dead_supervisor_record_when_a_legacy_listener_remains_unproven(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    supervisor_pid, listener_pid = 54041, 54042
    record = {
        "service": "firestore",
        "pid": supervisor_pid,
        "process_group": supervisor_pid,
        "port": cfg.firestore_port,
        "owned_ports": {"firestore": cfg.firestore_port},
        "ownership_marker": cli._marker(cfg, "firestore"),
    }
    cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
    cli._write_json(
        cfg.layout.port_manifest,
        {"ports": [{"service": "firestore", "port": cfg.firestore_port, "pid": supervisor_pid}]},
    )
    monkeypatch.setattr(safety, "process_exists", lambda _pid: False)
    monkeypatch.setattr(safety, "listening_pids", lambda port: (listener_pid,) if port == cfg.firestore_port else ())
    monkeypatch.setattr(os, "kill", lambda _pid, _sig: pytest.fail("legacy orphan must not be signalled"))

    stopped = cli._stop_owned(cfg)

    assert stopped is False
    assert cli._process_records(cfg) == [record]


def test_dev_down_reports_incomplete_shutdown_and_reset_preserves_ownership_evidence(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    record = {"service": "desktop", "pid": 54501, "diagnostic": "preserve-me"}
    cli._write_json(cfg.layout.process_manifest, {"processes": [record]})
    monkeypatch.setattr(cli, "_repo_root", lambda: REPO_ROOT)
    monkeypatch.setattr(config, "load_config", lambda *_args, **_kwargs: cfg)
    monkeypatch.setattr(
        cli,
        "stop_desktop_record",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(safety.SafetyError("legacy desktop record")),
    )
    monkeypatch.setattr(cli, "_save_manifests", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(cli, "_clear_state", lambda _cfg: pytest.fail("failed stop must not erase evidence"))

    assert cli.cmd_down(argparse.Namespace()) == 1
    assert cli.cmd_reset(argparse.Namespace()) == 1
    assert cli._process_records(cfg) == [record]


def test_restart_refuses_to_start_replacement_when_exact_stop_is_incomplete(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    cfg = _config(monkeypatch, tmp_path)
    record = {"service": "backend", "pid": 54601, "port": cfg.backend_port}
    monkeypatch.setattr(cli, "_service_record", lambda *_args: record)
    monkeypatch.setattr(cli, "_service_health", lambda *_args: (False, "unhealthy"))
    monkeypatch.setattr(cli, "_stop_single_service", lambda *_args: False)
    monkeypatch.setattr(
        cli.subprocess,
        "Popen",
        lambda *_args, **_kwargs: pytest.fail("replacement must not start after incomplete shutdown"),
    )

    with pytest.raises(safety.SafetyError, match="refusing replacement start"):
        cli._start_process(
            cfg,
            "backend",
            ["python", "-m", "backend"],
            cwd=cfg.repo_root,
            log_name="backend.log",
            port=cfg.backend_port,
        )


def test_supervisor_signal_is_delivered_once_to_the_supervisor_not_its_process_group(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    delivered: list[tuple[int, signal.Signals]] = []
    monkeypatch.setattr(os, "kill", lambda pid, sig: delivered.append((pid, sig)))
    monkeypatch.setattr(os, "killpg", lambda _pid, _sig: pytest.fail("group signal would double-deliver to child"))

    cli._signal_owned_supervisor(55051, "firestore", signal.SIGINT)

    assert delivered == [(55051, signal.SIGINT)]
