from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dev_harness import config, providers, safety
from dev_harness import cli

REPO_ROOT = Path(__file__).resolve().parents[3]
DEV_HARNESS_ROOT = REPO_ROOT / "scripts" / "dev-harness"


def _prepend_dev_harness_pythonpath(env: dict[str, str]) -> None:
    entries = [str(DEV_HARNESS_ROOT)]
    if existing := env.get("PYTHONPATH"):
        entries.append(existing)
    env["PYTHONPATH"] = os.pathsep.join(entries)


def test_child_pythonpath_uses_the_selected_host_separator(tmp_path: Path) -> None:
    env = {"PYTHONPATH": str(tmp_path / "existing")}
    first = tmp_path / "scripts" / "dev-harness"
    second = tmp_path / "backend"

    cli._prepend_pythonpath(env, first, second)

    assert env["PYTHONPATH"].split(os.pathsep) == [str(first), str(second), str(tmp_path / "existing")]


def test_offline_check_skips_provider_credentials(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("MODULATE_API_KEY", raising=False)
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT)

    missing, warnings = cli.prerequisite_report(cfg)

    assert not any("OPENAI_API_KEY" in item or "MODULATE_API_KEY" in item for item in missing)
    assert any("offline" in item for item in warnings)


def test_offline_app_commands_install_provider_fakes(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT)

    backend_command = cli._uvicorn_app_command(
        cfg,
        app_target="main:app",
        offline_app_target="testing.e2e.offline_backend_app:app",
        port=cfg.backend_port,
    )
    assert backend_command[3] == "testing.e2e.offline_backend_app:app"
    assert "--factory" not in backend_command
    assert not hasattr(cfg, "desktop_backend_port")


def test_app_service_topology_starts_only_the_canonical_backend(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT)
    started: list[tuple[str, list[str]]] = []

    def record_start(_cfg: config.HarnessConfig, service: str, command: list[str], **_kwargs: object) -> None:
        started.append((service, command))

    monkeypatch.setattr(cli, "_start_process", record_start)

    cli._start_app_services(cfg)

    assert [service for service, _command in started] == ["backend"]
    assert started[0][1][3] == "testing.e2e.offline_backend_app:app"


def test_real_app_commands_keep_production_entry_points(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT)

    command = cli._uvicorn_app_command(
        cfg,
        app_target="main:app",
        offline_app_target="testing.e2e.offline_backend_app:app",
        port=cfg.backend_port,
    )

    assert command[3] == "main:app"
    assert "--factory" not in command


def test_real_check_lists_provider_credentials(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "AGENTS.md").write_text("agents", encoding="utf-8")
    (repo / ".git").mkdir()
    (repo / "backend").mkdir()
    for key in ("OPENAI_API_KEY", "MODULATE_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(repo)

    missing, _warnings = cli.prerequisite_report(cfg)

    assert any("OPENAI_API_KEY" in item for item in missing)
    assert any("MODULATE_API_KEY" in item for item in missing)


def test_firebase_command_writes_the_configured_emulator_ports(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    monkeypatch.setenv("OMI_HARNESS_PORT_OFFSET", "321")
    cfg = config.load_config(REPO_ROOT, create_layout=True)
    command = cli._firebase_command(cfg)
    config_path = Path(command[command.index("--config") + 1])
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    assert payload["emulators"]["firestore"]["port"] == 8406
    assert payload["emulators"]["auth"]["port"] == 9420


def test_wait_health_returns_terminal_timeout_failures(monkeypatch: pytest.MonkeyPatch) -> None:
    cfg = SimpleNamespace(
        firestore_host="127.0.0.1:8085",
        auth_host="127.0.0.1:9099",
        backend_url="http://127.0.0.1:8000",
        redis_port=6380,
    )
    monkeypatch.setattr(cli, "_process_records", lambda _cfg: [])
    monkeypatch.setattr(cli, "_HEALTH_TIMEOUTS", {service: 0.0 for service in cli._HEALTH_TIMEOUTS})

    failures = cli._wait_health(cfg)

    assert len(failures) == 4
    assert any(item.startswith("backend: not healthy after 0s") for item in failures)


def test_wait_health_returns_dead_process_failure_and_clears_recovered_checks(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cfg = SimpleNamespace(
        firestore_host="127.0.0.1:8085",
        auth_host="127.0.0.1:9099",
        backend_url="http://127.0.0.1:8000",
        redis_port=6380,
    )
    monkeypatch.setattr(
        cli,
        "_process_records",
        lambda _cfg: [{"service": "backend", "pid": 4242, "log": "/tmp/backend.log"}],
    )
    monkeypatch.setattr(cli.safety, "process_exists", lambda pid: pid != 4242)
    monkeypatch.setattr(cli, "_port_open", lambda _host, _port: True)
    attempts = iter([(False, "connection refused"), (True, "HTTP 200"), (True, "HTTP 200")])
    monkeypatch.setattr(cli, "_http_ok", lambda _url, headers=None: next(attempts))
    monkeypatch.setattr(cli.time, "sleep", lambda _seconds: None)

    failures = cli._wait_health(cfg)

    assert failures == ["backend: process exited (pid=4242); check log: /tmp/backend.log"]


def test_reset_command_is_idempotent_with_temp_state(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["PROVIDER_MODE"] = "offline"
    env["OMI_LOCAL_STATE_ROOT"] = str(tmp_path / "state")
    _prepend_dev_harness_pythonpath(env)

    for _ in range(2):
        result = subprocess.run(
            [sys.executable, "-m", "dev_harness.cli", "reset"],
            cwd=REPO_ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert result.returncode == 0, result.stdout
        assert "Reset complete" in result.stdout

    layout = safety.layout_for_instance(REPO_ROOT, "default", env)
    assert layout.sentinel_path.is_file()
    safety.read_and_validate_sentinel(layout.state_root, repo_root=REPO_ROOT, instance="default")


def test_status_reports_synthetic_profiles_and_summary_path(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["PROVIDER_MODE"] = "offline"
    env["OMI_LOCAL_STATE_ROOT"] = str(tmp_path / "state")
    _prepend_dev_harness_pythonpath(env)

    initialized = subprocess.run(
        [sys.executable, "-m", "dev_harness.synthetic_profiles", "init"],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert initialized.returncode == 0, initialized.stdout

    result = subprocess.run(
        [sys.executable, "-m", "dev_harness.cli", "status"],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout
    assert "selected_user: alice" in result.stdout
    assert "seeded_users: alice, bob, local_default_user" in result.stdout
    assert "session_summary_path:" in result.stdout
    assert "PROVIDER_MODE=offline active" in result.stdout


def test_status_ignores_foreign_live_pid_when_selecting_active_provider_mode(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    cli._write_json(requested.layout.config_digest_path, {"provider_mode": "offline"})
    cli._write_json(
        requested.layout.process_manifest,
        {"processes": [{"service": "backend", "pid": os.getpid()}]},
    )

    active, requested_provider_mode = cli.active_runtime_config(requested)

    assert active.provider_mode == "real"
    assert requested_provider_mode is None


def test_status_prefers_owned_live_stack_provider_mode_over_ambient_request(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    marker = cli._marker(requested, "backend")
    offline = replace(requested, provider_mode="offline")
    offline_report = providers.ProviderPreflight(mode="offline", enabled_external_providers=())
    cli._write_json(requested.layout.config_digest_path, cli._config_digest(offline, offline_report))
    cli._write_json(
        requested.layout.process_manifest,
        {"processes": [{"service": "backend", "pid": os.getpid(), "ownership_marker": marker}]},
    )
    monkeypatch.setattr(safety, "command_line_for_pid", lambda _pid: f"pytest {marker}")

    active, requested_provider_mode = cli.active_runtime_config(requested)

    assert active.provider_mode == "offline"
    assert requested_provider_mode == "real"

    provider_report = cli.print_provider_status(active)
    assert provider_report.mode == "offline"


def test_status_rejects_owned_live_stack_without_complete_launch_evidence(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    cli._write_json(requested.layout.config_digest_path, {"provider_mode": "offline"})
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])

    with pytest.raises(RuntimeError, match="launch evidence is missing or invalid"):
        cli.active_runtime_config(requested)


def test_launch_contract_records_backend_source_and_dependency_fingerprint(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT, create_layout=True)

    digest = cli._config_digest(cfg, cli._current_provider_report(cfg))
    runtime_source = digest["runtime_source"]

    assert isinstance(runtime_source, dict)
    assert (
        runtime_source["repository_git_sha"]
        == subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True).strip()
    )
    assert len(str(runtime_source["fingerprint_sha256"])) == 64
    assert runtime_source["pathspec"] == list(cli.RUNTIME_SOURCE_PATHS)


def test_active_stack_rejects_stale_backend_source_or_dependency_fingerprint(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    report = cli._current_provider_report(requested)
    cli._write_json(requested.layout.config_digest_path, cli._config_digest(requested, report))
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])
    current_source = cli._runtime_source_contract(REPO_ROOT)
    stale_source = {**current_source, "fingerprint_sha256": "f" * 64}
    monkeypatch.setattr(cli, "_runtime_source_contract", lambda _repo_root: stale_source)

    with pytest.raises(RuntimeError, match="source or dependency fingerprint is stale"):
        cli.active_runtime_config(requested)


def test_status_uses_the_complete_recorded_launch_contract_not_ambient_configuration(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    monkeypatch.setenv("OMI_HARNESS_PORT_OFFSET", "20")
    launched = config.load_config(REPO_ROOT, create_layout=True)
    launched_report = providers.ProviderPreflight(
        mode="real",
        enabled_external_providers=("gemini",),
        fingerprints={"gemini": "launched-fingerprint"},
    )
    cli._write_json(launched.layout.config_digest_path, cli._config_digest(launched, launched_report))

    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_HARNESS_PORT_OFFSET", "40")
    requested = config.load_config(REPO_ROOT, create_layout=False)
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])

    active, requested_provider_mode = cli.active_runtime_config(requested)
    active_report = cli._runtime_provider_report(active)

    assert active.provider_mode == "real"
    assert active.backend_port == launched.backend_port
    assert active.firestore_port == launched.firestore_port
    assert requested_provider_mode == "offline"
    assert active_report.fingerprints == {"gemini": "launched-fingerprint"}


def test_same_mode_start_rejects_a_changed_complete_launch_contract(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    launched_report = providers.ProviderPreflight(
        mode="real",
        enabled_external_providers=("gemini",),
        fingerprints={"gemini": "old-fingerprint"},
    )
    requested_report = providers.ProviderPreflight(
        mode="real",
        enabled_external_providers=("gemini",),
        fingerprints={"gemini": "new-fingerprint"},
    )
    cli._write_json(requested.layout.config_digest_path, cli._config_digest(requested, launched_report))
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])
    monkeypatch.setattr(cli, "_current_provider_report", lambda _cfg: requested_report)

    with pytest.raises(RuntimeError, match="complete launch contract differs"):
        cli.prepare_provider_mode_for_start(requested)


def test_same_contract_start_reuses_processes_without_rewriting_launch_evidence(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    cfg = config.load_config(REPO_ROOT, create_layout=True)
    report = cli._current_provider_report(cfg)
    digest = cli._config_digest(cfg, report)
    digest["updated_at"] = "2026-09-03T00:00:00Z"
    cli._write_json(cfg.layout.config_digest_path, digest)
    original = cfg.layout.config_digest_path.read_bytes()

    monkeypatch.setattr(cli, "_repo_root", lambda: REPO_ROOT)
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])
    monkeypatch.setattr(cli, "prerequisite_report", lambda _cfg, _report=None: ([], []))
    monkeypatch.setattr(cli, "_start_services", lambda _cfg: None)
    monkeypatch.setattr(cli, "_wait_health", lambda _cfg: [])
    monkeypatch.setattr(cli.synthetic_profiles, "seed_profiles", lambda _cfg: None)

    assert cli.cmd_up(SimpleNamespace()) == 0
    assert cfg.layout.config_digest_path.read_bytes() == original


def test_check_validates_the_owned_active_mode_instead_of_ambient_credentials(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    for key in ("OPENAI_API_KEY", "MODULATE_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("PROVIDER_MODE", "real")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    marker = cli._marker(requested, "backend")
    offline = replace(requested, provider_mode="offline")
    offline_report = providers.ProviderPreflight(mode="offline", enabled_external_providers=())
    cli._write_json(requested.layout.config_digest_path, cli._config_digest(offline, offline_report))
    cli._write_json(
        requested.layout.process_manifest,
        {"processes": [{"service": "backend", "pid": os.getpid(), "ownership_marker": marker}]},
    )
    monkeypatch.setattr(safety, "command_line_for_pid", lambda _pid: f"pytest {marker}")
    monkeypatch.setattr(cli, "prerequisite_report", lambda _cfg, _report=None: ([], []))

    assert cli.cmd_check(SimpleNamespace()) == 0
    output = capsys.readouterr().out
    assert "provider_mode: offline" in output
    assert "requested_provider_mode: real (active stack takes precedence)" in output
    assert "All required prerequisites for this mode are present." in output


@pytest.mark.parametrize(("active_mode", "requested_mode"), [("real", "offline"), ("offline", "real")])
def test_start_rejects_relabelling_a_live_owned_provider_mode(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    active_mode: str,
    requested_mode: str,
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", requested_mode)
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    cli._write_json(requested.layout.config_digest_path, {"provider_mode": active_mode})
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])

    with pytest.raises(RuntimeError, match=f"already running in provider mode {active_mode}"):
        cli.prepare_provider_mode_for_start(requested)


def test_start_rejects_live_owned_services_without_a_proven_mode(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [{"service": "backend"}])

    with pytest.raises(RuntimeError, match="launch evidence is missing or invalid"):
        cli.prepare_provider_mode_for_start(requested)


def test_fresh_start_clears_stale_provider_mode_evidence(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("PROVIDER_MODE", "offline")
    monkeypatch.setenv("OMI_LOCAL_STATE_ROOT", str(tmp_path / "state"))
    requested = config.load_config(REPO_ROOT, create_layout=True)
    cli._write_json(requested.layout.config_digest_path, {"provider_mode": "real"})
    monkeypatch.setattr(cli, "_owned_live_process_records", lambda _cfg: [])

    assert cli.prepare_provider_mode_for_start(requested) is None
    assert not requested.layout.config_digest_path.exists()


def test_session_summary_is_local_emulator_non_activation(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["PROVIDER_MODE"] = "offline"
    env["OMI_LOCAL_STATE_ROOT"] = str(tmp_path / "state")
    _prepend_dev_harness_pythonpath(env)

    initialized = subprocess.run(
        [sys.executable, "-m", "dev_harness.synthetic_profiles", "init"],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert initialized.returncode == 0, initialized.stdout
    summary = subprocess.run(
        [sys.executable, "-m", "dev_harness.cli", "summary"],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert summary.returncode == 0, summary.stdout
    path = Path(summary.stdout.strip())
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["evidence_class"] == "LOCAL_EMULATOR_DEV"
    assert payload["activation_eligible"] is False
    assert payload["provider_mode"] == "offline"
    assert payload["selected_user"] == "alice"
    assert "before_digest" in payload["protected_state_digest"]
    assert any("Not DEV_CLOUD_PROOF" in item for item in payload["non_claims"])
