from __future__ import annotations

import sys
from dataclasses import replace
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dev_harness import cli, config, desktop_profile, providers, safety

LANGFUSE_VALUES = {
    "LANGFUSE_PUBLIC_KEY": "pk-lf-harness-fixture",
    "LANGFUSE_SECRET_KEY": "sk-lf-harness-fixture",
    "LANGFUSE_BASE_URL": "https://langfuse.example.invalid",
    "LANGFUSE_PROMPT_LABEL": "harness-evaluation",
}


@pytest.fixture
def cfg(tmp_path: Path) -> config.HarnessConfig:
    (tmp_path / "backend").mkdir()
    return config.HarnessConfig(
        repo_root=tmp_path,
        instance="langfuse-test",
        provider_mode="real",
        layout=safety.layout_for_instance(tmp_path, "langfuse-test"),
    )


@pytest.mark.parametrize("source", ["file", "ambient"])
@pytest.mark.parametrize("mode", ["real", "offline"])
def test_langfuse_configuration_is_real_backend_only(
    cfg: config.HarnessConfig, monkeypatch: pytest.MonkeyPatch, source: str, mode: str
) -> None:
    cfg = replace(cfg, provider_mode=mode)
    for name, value in LANGFUSE_VALUES.items():
        monkeypatch.delenv(name, raising=False)
        if source == "ambient":
            monkeypatch.setenv(name, value)
    if source == "file":
        config.secrets_file_path(cfg).write_text(
            "\n".join(f"{name}={value}" for name, value in LANGFUSE_VALUES.items()), encoding="utf-8"
        )

    backend = config.child_env_for(cfg, include_observability=True)
    infrastructure = config.child_env_for(cfg)
    for name, value in LANGFUSE_VALUES.items():
        assert backend.get(name) == (value if mode == "real" else None)
        assert name not in infrastructure
    profile = desktop_profile.resolve_profile(
        cfg, user="alice", seeded_users=("alice",), env={"OMI_APP_NAME": "omi-langfuse-test"}
    )
    app = desktop_profile.child_env(profile, parent=backend)
    assert not set(LANGFUSE_VALUES).intersection(app)


def test_langfuse_file_values_override_ambient_without_logging_values(
    cfg: config.HarnessConfig, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    for name in LANGFUSE_VALUES:
        monkeypatch.setenv(name, "ambient-fixture-value")
    config.secrets_file_path(cfg).write_text(
        "\n".join(f"{name}={value}" for name, value in LANGFUSE_VALUES.items()) + "\nLANGFUSE_HOST=ignored\n",
        encoding="utf-8",
    )
    backend = config.child_env_for(cfg, include_observability=True)
    assert {name: backend[name] for name in LANGFUSE_VALUES} == LANGFUSE_VALUES
    assert "LANGFUSE_HOST" not in backend
    cli.print_provider_status(cfg, providers.ProviderPreflight(mode="real", enabled_external_providers=()))
    output = capsys.readouterr().out
    assert all(value not in output for value in LANGFUSE_VALUES.values())
    assert all(f"{name}: file" in output for name in LANGFUSE_VALUES)


@pytest.mark.parametrize("name", LANGFUSE_VALUES)
def test_offline_environment_rejects_explicit_langfuse_configuration(name: str) -> None:
    with pytest.raises(safety.SafetyError, match="offline"):
        safety.build_child_env({}, provider_mode="offline", extra={name: LANGFUSE_VALUES[name]})


def test_backend_start_explicitly_admits_observability(
    cfg: config.HarnessConfig, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("LANGFUSE_SECRET_KEY", LANGFUSE_VALUES["LANGFUSE_SECRET_KEY"])
    started: list[dict[str, str]] = []
    monkeypatch.setattr(cli, "_start_process", lambda *args, **kwargs: started.append(kwargs["env"]))

    cli._start_app_services(cfg)

    assert len(started) == 1
    assert started[0]["LANGFUSE_SECRET_KEY"] == LANGFUSE_VALUES["LANGFUSE_SECRET_KEY"]
