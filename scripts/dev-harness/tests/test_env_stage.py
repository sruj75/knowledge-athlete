from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dev_harness import config, safety


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_child_env_for_offline_mode() -> None:
    cfg = config.HarnessConfig(
        repo_root=REPO_ROOT,
        instance="default",
        provider_mode="offline",
        layout=safety.layout_for_instance(REPO_ROOT, "default"),
    )
    child = config.child_env_for(cfg)
    assert child["PROVIDER_MODE"] == "offline"
    assert child["OMI_HARNESS_INSTANCE"] == "default"
    assert child["FIREBASE_API_KEY"] == config.LOCAL_FIREBASE_API_KEY
    assert child["OMI_LLM_STUB"] == "1"
    assert "MODULATE_API_KEY" not in child


def test_child_env_for_real_mode() -> None:
    cfg = config.HarnessConfig(
        repo_root=REPO_ROOT,
        instance="default",
        provider_mode="real",
        layout=safety.layout_for_instance(REPO_ROOT, "default"),
    )
    child = config.child_env_for(cfg)
    assert child["PROVIDER_MODE"] == "real"
    assert child["BASE_API_URL"] == cfg.backend_url


def test_nondefault_port_offset_propagates_to_surviving_harness_services() -> None:
    cfg = config.load_config(REPO_ROOT, env={"OMI_HARNESS_PORT_OFFSET": "321"})

    assert cfg.firestore_host == "127.0.0.1:8406"
    assert cfg.auth_host == "127.0.0.1:9420"
    assert cfg.redis_port == 6701
    assert cfg.automation_port == 48098
    assert cfg.firestore_websocket_port == 9471
    assert cfg.firebase_hub_port == 4721
    assert cfg.firebase_logging_port == 4821
    assert cfg.firebase_ui_port == 4321
    assert not hasattr(cfg, "typesense_port")
    assert cfg.backend_url == "http://127.0.0.1:8321"
    assert not hasattr(cfg, "desktop_backend_url")

    backend_env = config.child_env_for(cfg)
    assert backend_env["FIRESTORE_EMULATOR_HOST"] == cfg.firestore_host
    assert backend_env["FIREBASE_AUTH_EMULATOR_HOST"] == cfg.auth_host
    assert backend_env["REDIS_DB_PORT"] == "6701"
    assert "TYPESENSE_HOST" not in backend_env
    assert "TYPESENSE_HOST_PORT" not in backend_env
    assert "TYPESENSE_API_KEY" not in backend_env
    assert "TYPESENSE_PROTOCOL" not in backend_env
    assert backend_env["PORT"] == "8321"


def test_all_workspace_ports_must_be_distinct() -> None:
    with pytest.raises(safety.SafetyError, match="must be distinct"):
        config.load_config(
            REPO_ROOT,
            env={
                "OMI_HARNESS_BACKEND_PORT": "48000",
                "OMI_AUTOMATION_PORT": "48000",
            },
        )


def test_dev_instance_maps_the_conductor_port_block_to_one_workspace_contract(tmp_path: Path) -> None:
    fixture = tmp_path / "workspace"
    fixture.mkdir()
    (fixture / ".git").write_text("gitdir: /nonexistent\n", encoding="utf-8")
    script = REPO_ROOT / "scripts" / "dev-instance.sh"
    names = (
        "OMI_INSTANCE",
        "OMI_LOCAL_INSTANCE",
        "OMI_APP_NAME",
        "PYTHON_PORT",
        "OMI_HARNESS_BACKEND_PORT",
        "OMI_HARNESS_FIRESTORE_PORT",
        "OMI_HARNESS_AUTH_PORT",
        "OMI_HARNESS_REDIS_PORT",
        "OMI_AUTOMATION_PORT",
        "OMI_HARNESS_FIRESTORE_WEBSOCKET_PORT",
        "OMI_HARNESS_FIREBASE_HUB_PORT",
        "OMI_HARNESS_FIREBASE_LOGGING_PORT",
        "OMI_HARNESS_FIREBASE_UI_PORT",
    )
    command = f"source {script!s}; env"
    env = {
        "PATH": os.environ["PATH"],
        "CONDUCTOR_IS_LOCAL": "1",
        "CONDUCTOR_PORT": "55000",
        "OMI_INSTANCE": "workspace-alpha",
    }

    result = subprocess.run(
        ["bash", "-c", command],
        cwd=fixture,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    rendered_env = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    resolved = {name: rendered_env.get(name) for name in names}
    assert resolved == {
        "OMI_INSTANCE": "workspace-alpha",
        "OMI_LOCAL_INSTANCE": "workspace-alpha",
        "OMI_APP_NAME": "omi-workspace-alpha",
        "PYTHON_PORT": "55000",
        "OMI_HARNESS_BACKEND_PORT": "55000",
        "OMI_HARNESS_FIRESTORE_PORT": "55001",
        "OMI_HARNESS_AUTH_PORT": "55002",
        "OMI_HARNESS_REDIS_PORT": "55003",
        "OMI_AUTOMATION_PORT": "55004",
        "OMI_HARNESS_FIRESTORE_WEBSOCKET_PORT": "55005",
        "OMI_HARNESS_FIREBASE_HUB_PORT": "55006",
        "OMI_HARNESS_FIREBASE_LOGGING_PORT": "55007",
        "OMI_HARNESS_FIREBASE_UI_PORT": "55008",
    }


def test_dev_instance_preserves_explicit_ports_inside_a_conductor_workspace(tmp_path: Path) -> None:
    fixture = tmp_path / "workspace"
    fixture.mkdir()
    (fixture / ".git").write_text("gitdir: /nonexistent\n", encoding="utf-8")
    script = REPO_ROOT / "scripts" / "dev-instance.sh"
    command = (
        f"source {script!s}; "
        "printf '%s %s %s\\n' \"$PYTHON_PORT\" \"$OMI_HARNESS_BACKEND_PORT\" \"$OMI_AUTOMATION_PORT\""
    )
    env = {
        "PATH": os.environ["PATH"],
        "CONDUCTOR_IS_LOCAL": "1",
        "CONDUCTOR_PORT": "55000",
        "PYTHON_PORT": "55009",
        "OMI_HARNESS_BACKEND_PORT": "55009",
        "OMI_AUTOMATION_PORT": "55004",
    }

    result = subprocess.run(
        ["bash", "-c", command],
        cwd=fixture,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "55009 55009 55004"


def test_dev_instance_keeps_explicit_harness_offset_independent_of_ambient_conductor_ports(tmp_path: Path) -> None:
    fixture = tmp_path / "workspace"
    fixture.mkdir()
    (fixture / ".git").write_text("gitdir: /nonexistent\n", encoding="utf-8")
    script = REPO_ROOT / "scripts" / "dev-instance.sh"
    command = (
        f"source {script!s}; "
        "printf '%s %s %s\\n' "
        '"$OMI_HARNESS_BACKEND_PORT" "$OMI_HARNESS_FIRESTORE_PORT" "$OMI_AUTOMATION_PORT"'
    )
    env = {
        "PATH": os.environ["PATH"],
        "CONDUCTOR_IS_LOCAL": "1",
        "CONDUCTOR_PORT": "55000",
        "OMI_HARNESS_PORT_OFFSET": "321",
    }

    result = subprocess.run(
        ["bash", "-c", command],
        cwd=fixture,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "8321 8406 48098"


def test_dev_instance_rejects_a_non_numeric_harness_offset_before_port_arithmetic(tmp_path: Path) -> None:
    fixture = tmp_path / "workspace"
    fixture.mkdir()
    script = REPO_ROOT / "scripts" / "dev-instance.sh"
    result = subprocess.run(
        ["bash", "-c", f"source {script!s}"],
        cwd=fixture,
        env={"PATH": os.environ["PATH"], "OMI_HARNESS_PORT_OFFSET": "not-a-number"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert result.returncode != 0
    assert "OMI_HARNESS_PORT_OFFSET must be an integer" in result.stderr


@pytest.mark.parametrize(
    "port_env",
    (
        {
            "PYTHON_PORT": "55000",
            "OMI_HARNESS_BACKEND_PORT": "55009",
        },
        {
            "AUTOMATION_PORT": "55004",
            "OMI_AUTOMATION_PORT": "55009",
        },
    ),
)
def test_dev_instance_rejects_conflicting_port_aliases(tmp_path: Path, port_env: dict[str, str]) -> None:
    fixture = tmp_path / "workspace"
    fixture.mkdir()
    script = REPO_ROOT / "scripts" / "dev-instance.sh"
    result = subprocess.run(
        ["bash", "-c", f"source {script!s}"],
        cwd=fixture,
        env={"PATH": os.environ["PATH"], **port_env},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert result.returncode != 0
    assert "conflicting port aliases" in result.stderr
